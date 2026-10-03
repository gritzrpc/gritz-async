# frozen_string_literal: true

require "base64"
require "google/rpc/status_pb"
require "google/protobuf/well_known_types"

module Gritz
  module Transport
    class Async
      # Maps protocol-grpc streams and metadata onto the common RPC contract.
      # @api private
      class Call
        include Gritz::Call

        attr_reader :method_descriptor, :trailing_metadata, :deadline

        def initialize(method_descriptor:, protocol:, input:, output:, max_send_size:)
          @method_descriptor = method_descriptor
          @protocol = protocol
          @input = input
          @output = output
          @max_send_size = max_send_size
          @deadline = Time.now + protocol.deadline.remaining if protocol.deadline
          @trailing_metadata = {}
        end

        def metadata = @protocol.metadata.transform_values { |value| value.is_a?(Array) && value.one? ? value.first : value }
        def cancelled? = @protocol.request.stream.closed?
        def read = @input.read

        def write(message)
          if method_descriptor.output_type.encode(message).bytesize > @max_send_size
            raise Errors::ResourceExhausted, "response message exceeds max_send_message_size"
          end

          @protocol.response.body.release_headers
          @output.write(message)
        end

        def peer
          address = @protocol.request.remote_address
          return unless address

          "#{address.ipv6? ? 'ipv6' : 'ipv4'}:#{address.ip_address}:#{address.ip_port}"
        end

        def send_initial_metadata(metadata = {})
          merge_initial_metadata(metadata)
          @protocol.response.body.release_headers
        end

        def merge_initial_metadata(metadata = {})
          headers = @protocol.response.headers
          metadata.each do |key, value|
            headers.delete(key)
            Array(value).each { |item| headers.add(key, encode_metadata(key, item)) }
          end
        end

        def finish(error = nil)
          metadata = trailing_metadata.merge(error.is_a?(Gritz::Error) ? error.metadata : {})
          if error.is_a?(Gritz::Error) && !error.details.empty?
            details = error.details.map { |detail| detail.is_a?(Google::Protobuf::Any) ? detail : Google::Protobuf::Any.pack(detail) }
            metadata["grpc-status-details-bin"] = Google::Rpc::Status.encode(
              Google::Rpc::Status.new(code: error.grpc_code, message: error.message, details:)
            )
          end
          headers = @protocol.response.headers
          headers.trailer!
          metadata.each { |key, value| Array(value).each { |item| headers.add(key, encode_metadata(key, item)) } }
        ensure
          @protocol.response.body.release_headers
        end

        private

        def encode_metadata(key, value) = key.end_with?("-bin") ? Base64.strict_encode64(value) : value.to_s
      end
    end
  end
end

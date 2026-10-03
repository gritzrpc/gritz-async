# frozen_string_literal: true

require "protocol/grpc/interface"

module Gritz
  module Async
    # Protobuf service declarations that need no grpc C extension.
    # Uses protocol-grpc's rpc/stream DSL, with the same service name as the .proto file.
    # @api public
    class Service < Protocol::GRPC::Interface
      class << self
        attr_accessor :service_name

        def rpc_descs
          rpcs.transform_values do |rpc|
            Descriptor.new(rpc.request_class, rpc.response_class, rpc.streaming)
          end
        end
      end

      # Shapes protocol-grpc descriptors for the existing transport-independent router.
      # @api private
      Stream = Struct.new(:type)
      Descriptor = Struct.new(:request_type, :response_type, :kind) do
        def client_streamer? = kind == :client_streaming
        def server_streamer? = kind == :server_streaming
        def bidi_streamer? = kind == :bidirectional
        def input = client_streamer? || bidi_streamer? ? Stream.new(request_type) : request_type
        def output = server_streamer? || bidi_streamer? ? Stream.new(response_type) : response_type
      end
    end
  end
end

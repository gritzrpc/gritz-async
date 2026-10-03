# frozen_string_literal: true

require "async/grpc/dispatcher"
require "async/grpc/service"
require "securerandom"
require_relative "call"
require_relative "body"
require_relative "input"

module Gritz
  module Transport
    class Async
      # Reuses async-grpc's routing, framing, status and deadline implementation.
      # @api private
      class Bridge < ::Async::GRPC::Dispatcher
        def initialize(adapter, routes, config:, logger:)
          super()
          @adapter = adapter
          @routes = routes
          @config = config
          @logger = logger
          routes.values.group_by(&:service).each do |name, descriptors|
            interface = Class.new(Protocol::GRPC::Interface)
            descriptors.each do |descriptor|
              # Run unary handlers in child tasks too, so headers and cancellation
              # can progress while the application is waiting for I/O.
              interface.rpc(descriptor.name.to_sym, descriptor.input_type, descriptor.output_type, streaming: :bidirectional)
            end
            service = ::Async::GRPC::Service.new(interface, name)
            descriptors.each { |descriptor| service.define_singleton_method(descriptor.action) { nil } }
            register(service)
          end
        end

        protected

        def invoke_service(_service, _method, input, output, protocol)
          protocol.response.body = Body.new(output)
          descriptor = @routes.fetch(protocol.request.path)
          input = Input.new(input.body, limit: @config.max_receive_message_size, message_class: descriptor.input_type, encoding: input.encoding)
          call = Call.new(method_descriptor: descriptor, protocol:, input:, output:, max_send_size: @config.max_send_message_size)
          owner = ::Async::Task.current
          monitor = owner.async do
            sleep 0.01 until call.cancelled?
            owner.stop
          end
          terminal_error = nil
          begin
            size = protocol.request.headers.each.sum { |key, value| key.bytesize + Array(value).sum { |item| item.to_s.bytesize } + 32 }
            raise Errors::ResourceExhausted, "request metadata exceeds max_metadata_size" if size > @config.max_metadata_size

            @adapter.dispatch(call)
          rescue Gritz::Error => e
            terminal_error = e
            raise
          ensure
            begin
              call.finish(terminal_error)
            ensure
              monitor.stop
            end
          end
        end

        private

        def assign_status(protocol, error)
          unless error.is_a?(Gritz::Error) || error.is_a?(::Async::GRPC::DeadlineExceededError) || error.is_a?(Protocol::GRPC::Error)
            error_id = SecureRandom.uuid
            @logger.error("#{error_id}: #{error.full_message}")
            error = Errors::Internal.new("internal error (#{error_id})", metadata: { "error-id" => error_id })
            protocol.response.headers.add("error-id", error_id)
          end
          super
        end

        def status_for(error)
          return [error.grpc_code, error.message] if error.is_a?(Gritz::Error)

          super
        end
      end
    end
  end
end

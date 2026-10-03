# frozen_string_literal: true

require "protocol/grpc/body/readable"

module Gritz
  module Transport
    class Async
      # Bounds both the wire frame and the inflated payload before protobuf decoding.
      # @api private
      class Input < Protocol::GRPC::Body::Readable
        def initialize(body, limit:, **)
          super(body, **)
          @limit = limit
        end

        def read
          @prefix = true
          super
        end

        private

        def read_exactly(length)
          check_size!(length) unless @prefix
          @prefix = false
          super
        end

        def decompress(data)
          return super unless %w[gzip deflate].include?(encoding)

          inflater = Zlib::Inflate.new(Zlib::MAX_WBITS + (encoding == "gzip" ? 16 : 0))
          output = +"".b
          inflater.inflate(data) do |chunk|
            check_size!(output.bytesize + chunk.bytesize)
            output << chunk
          end
          raise Errors::InvalidArgument, "truncated compressed request" unless inflater.finished?

          output
        rescue Zlib::Error
          raise Errors::InvalidArgument, "invalid compressed request"
        ensure
          inflater&.close
        end

        def check_size!(size)
          raise Errors::ResourceExhausted, "request message exceeds max_receive_message_size" if size > @limit
        end
      end
    end
  end
end

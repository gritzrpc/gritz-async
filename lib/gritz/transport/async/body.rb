# frozen_string_literal: true

require "async/condition"
require "protocol/http/body/wrapper"

module Gritz
  module Transport
    class Async
      # Delays HTTP headers until the handler sends metadata, data or a final status.
      # @api private
      class Body < Protocol::HTTP::Body::Wrapper
        def initialize(body)
          super
          @headers_ready = ::Async::Condition.new
        end

        def release_headers
          @released = true
          @headers_ready.signal
        end

        def length
          @headers_ready.wait until @released
          super
        end
      end
    end
  end
end

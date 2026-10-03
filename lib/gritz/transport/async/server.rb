# frozen_string_literal: true

require "async/http/protocol/http2"

module Gritz
  module Transport
    class Async
      # Owns HTTP/2 connections so shutdown can send GOAWAY and retain active streams.
      # @api private
      class Server
        class Connection < ::Async::HTTP::Protocol::HTTP2::Server
          attr_reader :last_stream_id

          def drain!
            @last_stream_id = remote_stream_id
            frame = Protocol::HTTP2::GoawayFrame.new
            frame.pack(@last_stream_id, 0, "")
            # Upstream send_goaway also closes the reader, losing active responses.
            write_frame(frame)
          end
        end

        # A client may reset its stream while the handler is still completing.
        module ResponseLifecycle
          def send_response(response)
            return response&.close if stream.closed?

            super
          rescue Protocol::HTTP2::ProtocolError
            raise unless stream.closed?

            response&.close
          end
        end

        def initialize(app, logger)
          @app = app
          @logger = logger
          @connections = {}
        end

        def accept(peer, _address)
          connection = Connection.new(::IO::Stream(peer))
          connection.read_connection_preface(::Async::HTTP::Protocol::HTTP2::SERVER_SETTINGS)
          connection.drain! if @stopping
          connection.start_connection
          @connections[connection] = true
          connection.each do |request|
            request.scheme ||= "http"
            request.extend(ResponseLifecycle)
            next if request.stream.closed?

            if connection.last_stream_id && request.stream.id > connection.last_stream_id
              # Decode frames normally to retain HPACK and flow-control state.
              request.stream.send_reset_stream(Protocol::HTTP2::REFUSED_STREAM)
              next
            end

            @app.call(request)
          end
        rescue IOError, SystemCallError, Protocol::HTTP2::Error => e
          @logger.debug("Async connection closed: #{e.class}")
        ensure
          @connections.delete(connection)
          connection&.close
        end

        def stop(deadline:)
          @stopping = true
          @connections.keys.each do |connection| # rubocop:disable Style/HashEachMethods -- IO can yield while other connections change.
            connection.drain! unless connection.closed?
          rescue IOError, SystemCallError, Protocol::HTTP2::Error
            connection.close
          end
          until @connections.empty? || Time.now >= deadline
            break if @connections.keys.all? { |connection| connection.streams.empty? }

            sleep 0.001
          end
          @connections.keys.each(&:close) # rubocop:disable Style/HashEachMethods -- Closing can yield and change connections.
        end
      end
    end
  end
end

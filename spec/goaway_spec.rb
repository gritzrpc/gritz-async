# frozen_string_literal: true

require "spec_helper"
require "protocol/http2/client"

RSpec.describe "GOAWAY frame races" do
  it "retains HPACK state from an unaccepted stream for an existing stream's trailers" do
    Async do
      peer, remote = UNIXSocket.pair
      server = Gritz::Transport::Async::Server::Connection.new(IO::Stream(peer))
      client = Protocol::HTTP2::Client.new(Protocol::HTTP2::Framer.new(IO::Stream(remote)))
      server.state = client.state = :open
      send_headers = lambda do |id, headers, finished = false|
        flags = Protocol::HTTP2::END_HEADERS | (finished ? Protocol::HTTP2::END_STREAM : 0)
        frame = Protocol::HTTP2::HeadersFrame.new(id, flags)
        frame.pack(client.encode_headers(headers))
        client.write_frame(frame)
        server.read_frame
      end
      headers = [[":method", "POST"], [":scheme", "http"], [":authority", "example"], [":path", "/test"]]
      send_headers.call(1, headers)
      request = server[1].request
      server.drain!
      # This stream can already be in flight when the peer receives GOAWAY.
      send_headers.call(3, [*headers, %w[x-race dynamic-value]])
      server[3]&.send_reset_stream(Protocol::HTTP2::REFUSED_STREAM)
      expect { send_headers.call(1, [%w[x-race dynamic-value]], true) }.not_to raise_error
      expect(request.headers["x-race"].to_s).to eq("dynamic-value")
    ensure
      server&.close
      client&.close
      peer&.close unless peer&.closed?
      remote&.close unless remote&.closed?
    end.wait
  end
end

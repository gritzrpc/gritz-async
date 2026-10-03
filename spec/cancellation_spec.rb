# frozen_string_literal: true

require "spec_helper"
require "async/http/client"
require "async/http/endpoint"
$LOAD_PATH.unshift File.expand_path("fixtures/hello", __dir__)
require "hello_services_pb"

RSpec.describe "Async call lifecycle" do
  def with_server(&action)
    controller = Class.new(Gritz::Controller) do
      bind Helloworld::Greeter::Service
      define_method(:say_hello, &action)
    end
    config = Gritz::Configuration.new
    config.transport = :async
    config.listener_strategy = :inherited_fd
    config.bind = "127.0.0.1:0"
    config.shutdown_timeout = 0.2
    Gritz::Testing::Server.start(config, controllers: [controller]) { |server| yield_server(server) }
  end

  it "sends initial unary metadata before the handler finishes" do
    gate = Queue.new
    @test = lambda do |server|
      Async do
        endpoint = Async::HTTP::Endpoint.parse("http://#{server.address}", protocol: Async::HTTP::Protocol::HTTP2)
        client = Async::HTTP::Client.new(endpoint)
        request = Helloworld::HelloRequest.encode(Helloworld::HelloRequest.new)
        headers = Protocol::GRPC::Metadata.build
        response = Async::Task.current.with_timeout(0.5) do
          client.post("/helloworld.Greeter/SayHello", headers, [0, request.bytesize].pack("CN") + request)
        end
        expect(Array(response.headers["early"])).to eq(["yes"])
        gate << true
        response.finish
      ensure
        response&.close
        client&.close
      end.wait
    end
    with_server do
      context.call.send_initial_metadata("early" => "yes")
      gate.pop
      Helloworld::HelloReply.new(message: "done")
    end
  ensure
    gate << true
  end

  it "unwinds a cancelled blocked controller and preserves the connection for another RPC" do
    entered = Queue.new
    finished = Queue.new
    @test = lambda do |server|
      client = Helloworld::Greeter::Stub.new(server.address, :this_channel_is_insecure)
      operation = client.say_hello(Helloworld::HelloRequest.new, return_op: true, deadline: Time.now + 5)
      caller = Thread.new do
        operation.execute
      rescue GRPC::BadStatus => e
        e
      end
      expect(entered.pop(timeout: 2)).to be(true)
      operation.cancel
      expect(caller.join(2)).not_to be_nil
      expect(caller.value).to be_a(GRPC::Cancelled)
      expect(finished.pop(timeout: 0.5)).to be(true)
      expect(client.say_hello(Helloworld::HelloRequest.new(name: "next"), deadline: Time.now + 2).message).to eq("next")
    ensure
      operation&.cancel
      caller&.join(2)
    end
    with_server do
      return Helloworld::HelloReply.new(message: "next") if request.message.name == "next"

      entered << true
      begin
        Queue.new.pop
      ensure
        finished << context.call.cancelled?
      end
    end
  end

  def yield_server(server) = @test.call(server)
end

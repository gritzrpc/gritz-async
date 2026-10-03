# frozen_string_literal: true

require "spec_helper"
require "gritz/testing/transport_contract"
$LOAD_PATH.unshift File.expand_path("fixtures/hello", __dir__)
require "hello_services_pb"

RSpec.describe "Async transport contract" do
  service = Class.new(Gritz::Async::Service) do
    self.service_name = "helloworld.Greeter"
    rpc :SayHello, Helloworld::HelloRequest, Helloworld::HelloReply
    rpc :ListGreetings, Helloworld::HelloRequest, stream(Helloworld::HelloReply)
    rpc :RecordNames, stream(Helloworld::HelloRequest), Helloworld::HelloReply
    rpc :Chat, stream(Helloworld::HelloRequest), stream(Helloworld::HelloReply)
  end
  include_examples Gritz::Testing::TransportContract,
                   adapter: :async, service:, stub: Helloworld::Greeter::Stub,
                   request: Helloworld::HelloRequest, reply: Helloworld::HelloReply
end

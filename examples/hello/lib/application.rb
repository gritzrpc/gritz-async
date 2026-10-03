# frozen_string_literal: true

require "gritz/async"
require_relative "hello_pb"

class Greeter < Gritz::Async::Service
  self.service_name = "helloworld.Greeter"
  rpc :SayHello, Helloworld::HelloRequest, Helloworld::HelloReply
  rpc :ListGreetings, Helloworld::HelloRequest, stream(Helloworld::HelloReply)
  rpc :RecordNames, stream(Helloworld::HelloRequest), Helloworld::HelloReply
  rpc :Chat, stream(Helloworld::HelloRequest), stream(Helloworld::HelloReply)
end

class GreeterController < Gritz::Controller # rubocop:disable Style/OneClassPerFile -- Keep the small sample together.
  bind Greeter

  def say_hello = Helloworld::HelloReply.new(message: "Hello, #{request.message.name}")

  def list_greetings
    3.times { |i| stream.write(Helloworld::HelloReply.new(message: "#{request.message.name}:#{i}")) }
  end

  def record_names = Helloworld::HelloReply.new(count: request.each_message.count)

  def chat
    request.each_message { |message| stream.write(Helloworld::HelloReply.new(message: message.name)) }
  end
end

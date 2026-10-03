# frozen_string_literal: true

require "spec_helper"
require "zlib"
$LOAD_PATH.unshift File.expand_path("fixtures/hello", __dir__)
require "hello_services_pb"

RSpec.describe "Async resource limits" do
  def server(**options, &block)
    controller = Class.new(Gritz::Controller) do
      bind Helloworld::Greeter::Service
      def say_hello = Helloworld::HelloReply.new(message: request.message.name)
    end
    config = Gritz::Configuration.new
    config.transport = :async
    config.bind = "127.0.0.1:0"
    options.each { |name, value| config.public_send("#{name}=", value) }
    Gritz::Testing::Server.start(config, controllers: [controller]) do |instance|
      block.call(Helloworld::Greeter::Stub.new(instance.address, :this_channel_is_insecure), instance)
    end
  end

  it "bounds an incoming frame before reading its payload" do
    server(max_receive_message_size: 16) do |client|
      expect { client.say_hello(Helloworld::HelloRequest.new(name: "a" * 100)) }.to raise_error(GRPC::ResourceExhausted)
    end
  end

  it "bounds a decompressed request" do
    server(max_receive_message_size: 1024) do |_client, instance|
      compressed = Helloworld::Greeter::Stub.new(instance.address, :this_channel_is_insecure,
                                                 channel_args: { "grpc.default_compression_algorithm" => 2 })
      expect { compressed.say_hello(Helloworld::HelloRequest.new(name: "a" * 4096)) }.to raise_error(GRPC::ResourceExhausted)
    end
  end

  it "bounds serialized responses" do
    server(max_send_message_size: 16) do |client|
      expect { client.say_hello(Helloworld::HelloRequest.new(name: "a" * 100)) }.to raise_error(GRPC::ResourceExhausted)
    end
  end

  it "bounds incoming metadata" do
    server(max_metadata_size: 512) do |client|
      expect { client.say_hello(Helloworld::HelloRequest.new, metadata: { "large" => "a" * 2048 }) }.to raise_error(GRPC::ResourceExhausted)
    end
  end
end

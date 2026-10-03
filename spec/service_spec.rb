# frozen_string_literal: true

require "spec_helper"
require "open3"
require "rbconfig"

RSpec.describe "Pure Ruby service definitions" do
  it "builds all four route types from protobuf-only service declarations" do
    source = <<~RUBY
      require "gritz/async"
      require_relative "spec/fixtures/hello/hello_pb"
      class PureGreeter < Gritz::Async::Service
        self.service_name = "helloworld.Greeter"
        rpc :SayHello, Helloworld::HelloRequest, Helloworld::HelloReply
        rpc :ListGreetings, Helloworld::HelloRequest, stream(Helloworld::HelloReply)
        rpc :RecordNames, stream(Helloworld::HelloRequest), Helloworld::HelloReply
        rpc :Chat, stream(Helloworld::HelloRequest), stream(Helloworld::HelloReply)
      end
      controller = Class.new(Gritz::Controller) { bind PureGreeter }
      routes = Gritz::Router.new(controllers: [controller]).routes.values
      abort "wrong types" unless routes.map(&:kind) == [:unary, :server_streaming, :client_streaming, :bidi]
      abort "loaded grpc" if defined?(GRPC)
    RUBY
    _, stderr, status = Open3.capture3(RbConfig.ruby, "-Ilib", "-e", source)
    expect(status.success?).to be(true), stderr
  end
end

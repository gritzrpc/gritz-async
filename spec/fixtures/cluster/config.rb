# frozen_string_literal: true

require "gritz/async"
abort "C-core loaded in Async master" if defined?(GRPC)
require_relative "../hello/hello_pb"

class PureGreeter < Gritz::Async::Service
  self.service_name = "helloworld.Greeter"
  rpc :SayHello, Helloworld::HelloRequest, Helloworld::HelloReply
end

class PureController < Gritz::Controller
  bind PureGreeter
  def say_hello = Helloworld::HelloReply.new(message: Process.pid.to_s, count: Process.pid)
end

transport :async
listener_strategy :inherited_fd
workers 2
bind "127.0.0.1:0"
admin_bind "127.0.0.1:0"
drain_delay 0
shutdown_timeout 2
worker_boot_timeout 5
status_interval 0.05
preload_app!
register_controller PureController

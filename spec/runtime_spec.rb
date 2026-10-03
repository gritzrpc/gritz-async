# frozen_string_literal: true

require "spec_helper"
$LOAD_PATH.unshift File.expand_path("fixtures/hello", __dir__)
require "hello_services_pb"

RSpec.describe Gritz::Transport::Async do
  def config(&action)
    controller = Class.new(Gritz::Controller) do
      bind Helloworld::Greeter::Service
      define_method(:say_hello, &action) if action
    end
    Gritz::Configuration.new.tap do |settings|
      settings.transport = :async
      settings.bind = "127.0.0.1:0"
      settings.controllers = [controller]
    end
  end

  it "runs concurrent RPCs in isolated fibers on one thread and bounds overload" do
    entered = Queue.new
    gate = Queue.new
    settings = config do
      entered << [Thread.current.object_id, Fiber.current.object_id, context.request_id]
      gate.pop
      Helloworld::HelloReply.new(message: Gritz::Context.current.request_id)
    end
    settings.threads = settings.max_waiting_requests = 1
    Gritz::Testing::Server.start(settings) do |server|
      client = Helloworld::Greeter::Stub.new(server.address, :this_channel_is_insecure)
      callers = %w[first second].map do |id|
        Thread.new { client.say_hello(Helloworld::HelloRequest.new, metadata: { "x-request-id" => id }, deadline: Time.now + 3) }
      end
      observations = 2.times.map { entered.pop(timeout: 2) }
      expect(observations.map(&:first).uniq.size).to eq(1)
      expect(observations.map { |row| row[1] }.uniq.size).to eq(2)
      expect(server.transport.stats).to include(inflight: 2, capacity: 2)
      expect { client.say_hello(Helloworld::HelloRequest.new) }.to raise_error(GRPC::ResourceExhausted)
      expect(server.transport.stats).to include(rejected_total: 1, requests_total: 2)
      2.times { gate << true }
      expect(callers.map { |thread| thread.value.message }).to eq(%w[first second])
      expect(server.transport.stats).to include(inflight: 0)
    ensure
      2.times { gate << true }
      callers&.each { |thread| thread.join(3) }
    end
  end

  it "retains ownership of an inherited listener and cleans up an unstarted adapter" do
    settings = config
    dispatcher = Gritz::Dispatcher.new(router: Gritz::Router.new(controllers: settings.controllers))
    adapter = described_class.new(config: settings, dispatcher:, logger: Logger.new(File::NULL))
    listener = Gritz::Supervisor::Listener.bind("127.0.0.1:0")
    expect { adapter.start }.to raise_error(ArgumentError, /bind/)
    expect(adapter.bind(listener)).to eq(listener.local_address.ip_port)
    expect { adapter.bind(listener) }.to raise_error(ArgumentError, /bound/)
    adapter.kill
    expect(listener).not_to be_closed
    expect { adapter.start }.to raise_error(ArgumentError, /stopped/)
  ensure
    adapter&.kill
    listener&.close
  end

  it "reports unhealthy checks and keeps draining sticky" do
    settings = config { Helloworld::HelloReply.new }
    settings.health_checks[:database] = -> { raise "disconnected" }
    Gritz::Testing::Server.start(settings) do |server|
      adapter = server.transport
      expect(adapter.refresh_health).to be(false)
      settings.health_checks[:database] = -> { true }
      expect(adapter.refresh_health).to be(true)
      adapter.drain!
      expect(adapter.refresh_health).to be(false)
      expect(adapter.update_health(ready: true)).to be(false)
    end
  end

  it "rejects unsupported security and reflection settings before binding" do
    settings = config
    dispatcher = Gritz::Dispatcher.new(router: Gritz::Router.new(controllers: settings.controllers))
    settings.reflection = true
    adapter = described_class.new(config: settings, dispatcher:, logger: Logger.new(File::NULL))
    expect { adapter.bind }.to raise_error(Gritz::ConfigurationError, /reflection/)
    settings.reflection = false
    settings.tls = { cert: "server.pem" }
    expect { adapter.bind }.to raise_error(Gritz::ConfigurationError, /TLS/)
    settings.tls = {}
    settings.keepalive_time = 2
    expect { adapter.bind }.to raise_error(Gritz::ConfigurationError, /keepalive_time/)
  end
end

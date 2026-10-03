# frozen_string_literal: true

require "spec_helper"
require "gritz/testing/cluster"
$LOAD_PATH.unshift File.expand_path("fixtures/hello", __dir__)
require "hello_services_pb"

RSpec.describe "Inherited Async cluster" do
  let(:config) { File.expand_path("fixtures/cluster/config.rb", __dir__) }
  let(:command) do
    [RbConfig.ruby, "-Ilib", "-rgritz/async", "-e",
     "exit Gritz::CLI.new(launch: true, status_io: IO.for_fd(3)).run(ARGV)", "--", "start", "-C", config]
  end

  it "keeps one socket across worker kill, resize, phased restart and hot reexec" do
    Gritz::Testing::Cluster.start(config_path: config, command:) do |cluster|
      cluster.wait_until(timeout: 10) { |row| row[:workers].size == 2 && row[:workers].all? { |worker| worker[:state] == "ready" } }
      status = cluster.status
      port = status[:workers].first[:port]
      expect(status[:workers].map { |worker| worker[:port] }.uniq).to eq([port])
      original = status[:workers].map { |worker| worker[:pid] }
      client = Helloworld::Greeter::Stub.new("127.0.0.1:#{port}", :this_channel_is_insecure)
      expect(original).to include(client.say_hello(Helloworld::HelloRequest.new, deadline: Time.now + 3).count)
      Process.kill("KILL", original.first)
      cluster.wait_until(timeout: 10) do |row|
        pids = row[:workers].map { |worker| worker[:pid] }
        pids.size == 2 && !pids.include?(original.first) && row[:workers].all? { |worker| worker[:state] == "ready" }
      end
      replaced = cluster.status
      cluster.signal("TTIN")
      cluster.wait_until(timeout: 10) { |row| row[:workers].size == 3 && row[:workers].all? { |worker| worker[:state] == "ready" } }
      cluster.signal("TTOU")
      cluster.wait_until(timeout: 10) { |row| row[:workers].size == 2 && row[:workers].all? { |worker| worker[:state] == "ready" } }
      before = replaced[:workers].map { |worker| worker[:pid] }
      cluster.signal("USR1")
      cluster.wait_until(timeout: 10) do |row|
        row[:workers].size == 2 && !row[:workers].map { |worker| worker[:pid] }.intersect?(before) &&
          row[:workers].all? { |worker| worker[:state] == "ready" }
      end
      old_master = cluster.status[:pid]
      cluster.signal("USR2")
      cluster.wait_until(timeout: 10) do |row|
        row[:pid] != old_master && row[:masters].size == 1 && row[:workers].size == 2 &&
          row[:workers].all? { |worker| worker[:state] == "ready" }
      end
      fresh = cluster.status
      expect(fresh[:workers].map { |worker| worker[:port] }.uniq).to eq([port])
      client = Helloworld::Greeter::Stub.new("127.0.0.1:#{port}", :this_channel_is_insecure)
      expect(fresh[:workers].map { |worker| worker[:pid] }).to include(client.say_hello(Helloworld::HelloRequest.new, deadline: Time.now + 3).count)
    end
  end

  it "recycles a worker by request count while retaining the ephemeral listener" do
    Gritz::Testing::Cluster.start(config_path: config, command:, env: { "GRITZ_WORKER_RECYCLE" => '{"max_requests":1}' }) do |cluster|
      cluster.wait_until(timeout: 10) { |row| row[:workers].size == 2 && row[:workers].all? { |worker| worker[:state] == "ready" } }
      port = cluster.status[:workers].first[:port]
      client = Helloworld::Greeter::Stub.new("127.0.0.1:#{port}", :this_channel_is_insecure)
      retired = client.say_hello(Helloworld::HelloRequest.new, deadline: Time.now + 3).count
      cluster.wait_until(timeout: 10) do |row|
        row[:workers].size == 2 && row[:workers].none? { |worker| worker[:pid] == retired } &&
          row[:workers].all? { |worker| worker[:state] == "ready" }
      end
      expect(cluster.status[:workers].map { |worker| worker[:port] }.uniq).to eq([port])
      client = Helloworld::Greeter::Stub.new("127.0.0.1:#{port}", :this_channel_is_insecure)
      expect(client.say_hello(Helloworld::HelloRequest.new, deadline: Time.now + 3).count).not_to eq(retired)
    end
  end
end

# frozen_string_literal: true

require "spec_helper"
require "open3"
require "rbconfig"

RSpec.describe "Async adapter" do
  it "provides a transport without loading the grpc C extension" do
    source = <<~RUBY
      require "gritz/async"
      abort "missing Async transport" unless defined?(Gritz::Transport::Async)
      abort "loaded grpc" if defined?(GRPC) || $LOADED_FEATURES.any? { |file| file.include?("grpc_c") }
      abort "missing fibers" unless Gritz::Transport::Async.capabilities.include?(:fiber)
    RUBY
    _, stderr, status = Open3.capture3(RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__), "-e", source)
    expect(status.success?).to be(true), stderr
  end
end

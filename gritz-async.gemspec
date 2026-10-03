# frozen_string_literal: true

require_relative "lib/gritz/async/version"

Gem::Specification.new do |spec|
  spec.name = "gritz-async"
  spec.version = Gritz::Async::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]
  spec.summary = "Fiber-based gRPC transport for Gritz"
  spec.description = "The Async gRPC adapter for Gritz, with inherited listeners and transport-independent controllers."
  spec.homepage = "https://github.com/gritzrpc/gritz-async"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"
  spec.metadata = {
    "allowed_push_host" => "https://rubygems.org",
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }
  spec.files = Dir.chdir(__dir__) { Dir["lib/**/*.rb", "exe/*", "README.md", "LICENSE.txt", "CHANGELOG.md"] }
  spec.require_paths = ["lib"]
  spec.bindir = "exe"
  spec.executables = ["gritz"]
  spec.add_dependency "async-grpc", "~> 0.10.0"
  spec.add_dependency "async-http", "~> 0.105.0"
  spec.add_dependency "googleapis-common-protos-types", ">= 1.20", "< 2"
  spec.add_dependency "gritz-core", "= 0.6.1"
  spec.add_dependency "protocol-grpc", "~> 0.17.0"
  spec.add_dependency "protocol-http2", "~> 0.29.1"
end

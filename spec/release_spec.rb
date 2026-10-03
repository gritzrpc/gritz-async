# frozen_string_literal: true

require "spec_helper"
require "open3"

RSpec.describe "Async release package" do
  it "packages the public entrypoint and executable without runtime C-core dependencies" do
    spec = Gem::Specification.load("gritz-async.gemspec")
    expect(spec.version.to_s).to eq(Gritz::Async::VERSION)
    expect(spec.files).to include("lib/gritz/async.rb", "lib/gritz/async/service.rb", "exe/gritz", "CHANGELOG.md")
    expect(spec.dependencies.map(&:name)).to include("gritz-core", "async-grpc")
    expect(spec.dependencies.map(&:name)).not_to include("grpc", "gritz-native", "gritz")
    expect(spec.executables).to eq(["gritz"])
    notes, status = Open3.capture2e(RbConfig.ruby, "tools/release_notes.rb", "0.1.0")
    expect(status.success?).to be(true), notes
    expect(notes.strip).to eq("Initial release.")
  end
end

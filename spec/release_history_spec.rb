# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

RSpec.describe "published release history" do
  it "ignores failed tags when checking user impact" do
    Dir.mktmpdir do |directory|
      FileUtils.mkdir_p(File.join(directory, "tools"))
      FileUtils.mkdir_p(File.join(directory, "lib/gritz/async"))
      FileUtils.cp("tools/check_release.rb", File.join(directory, "tools/check_release.rb"))
      File.write(File.join(directory, "lib/gritz/async/version.rb"), "module Gritz; module Async; VERSION = '0.1.2'; end; end\n")
      File.write(File.join(directory, "gritz-async.gemspec"), "# release fixture\n")
      File.write(File.join(directory, "lib/handler.rb"), "# initial runtime\n")
      git = lambda do |*arguments|
        output, status = Open3.capture2e("git", "-C", directory, *arguments)
        raise output unless status.success?
      end
      git.call("init", "--quiet")
      git.call("config", "user.name", "Release test")
      git.call("config", "user.email", "release-test@example.invalid")
      git.call("add", ".")
      git.call("commit", "--quiet", "-m", "feat: add runtime")
      git.call("tag", "v0.1.0")
      File.write(File.join(directory, "lib/handler.rb"), "# changed runtime\n")
      git.call("add", ".")
      git.call("commit", "--quiet", "-m", "fix: improve runtime")
      git.call("tag", "v0.1.1")
      File.write(File.join(directory, "curl"), "#!/bin/sh\nprintf '%s\\n' \"$PUBLISHED_VERSIONS\"\n")
      File.chmod(0o755, File.join(directory, "curl"))
      check = lambda do |versions|
        env = { "RUBYOPT" => nil, "PATH" => "#{directory}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}",
                "GITHUB_REF_NAME" => "v0.1.2", "PUBLISHED_VERSIONS" => JSON.generate(versions.map { |number| { number: } }) }
        Open3.capture3(env, RbConfig.ruby, "tools/check_release.rb", chdir: directory)
      end
      output, error, status = check.call(["0.1.0"])
      expect(status).to be_success, "#{output}#{error}"
      expect(check.call(%w[0.1.0 0.1.1]).last).not_to be_success
      expect(check.call([]).last).not_to be_success
    end
  end
end

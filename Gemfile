# frozen_string_literal: true

source "https://rubygems.org"
gemspec
unless ENV["GRITZ_RELEASE"] == "1"
  gem "gritz-core", git: "https://github.com/gritzrpc/gritz-core.git", branch: "main"
end

group :development, :test do
  gem "bundler-audit", "~> 0.9"
  gem "grpc", ">= 1.83", "< 2"
  gem "rake", "~> 13.0"
  gem "rspec", "~> 3.0"
  gem "rubocop", "~> 1.75"
  gem "simplecov", "~> 0.22.0"
end

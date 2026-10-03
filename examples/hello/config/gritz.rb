# frozen_string_literal: true

require "gritz/async"
require_relative "../lib/application"

transport :async
listener_strategy :inherited_fd
bind "127.0.0.1:50051"
workers Integer(ENV.fetch("WEB_CONCURRENCY", "0"))
register_controller GreeterController
preload_app!

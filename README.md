# Gritz Async

Experimental Fiber-based gRPC server adapter for [Gritz](https://github.com/gritzrpc/gritz-core), built on `async-grpc`. Requires CRuby 3.3+. Each RPC runs in a Fiber; workers inherit a TCP listener that stays open across master replacement.

The runtime depends on `gritz-core`, `async-grpc` and their protobuf/HTTP dependencies. It does not install the official `grpc` gem or `gritz-native`. The `gritz` meta gem selects Native, so Async applications install `gritz-async` instead.

## Install

```ruby
gem "gritz-async", "~> 0.1.4"
```

The 0.1.4 release requires Core 0.9.0. Earlier 0.1 releases support Core 0.6. See [release instructions](docs/guides/releasing.md).

## Quick start

Generate protobuf **messages** with `protoc --ruby_out=lib hello.proto`. Declare the service with the matching protobuf package and service name; the generated `*_services_pb.rb` file uses the official grpc gem and is unnecessary for the Async server.

```ruby
# config/gritz.rb
require "gritz/async"
require_relative "../lib/hello_pb"

class Greeter < Gritz::Async::Service
  self.service_name = "helloworld.Greeter"
  rpc :SayHello, Helloworld::HelloRequest, Helloworld::HelloReply
end

class GreeterController < Gritz::Controller
  bind Greeter
  def say_hello
    Helloworld::HelloReply.new(message: "Hello, #{request.message.name}")
  end
end

transport :async
listener_strategy :inherited_fd
workers 0
bind "127.0.0.1:50051"
register_controller GreeterController
```

```sh
bundle exec gritz routes -C config/gritz.rb
bundle exec gritz check -C config/gritz.rb
bundle exec gritz start -C config/gritz.rb
grpcurl -plaintext -proto hello.proto -d '{"name":"Ruby"}' \
  127.0.0.1:50051 helloworld.Greeter/SayHello
```

The [hello example](examples/hello) implements unary, server-streaming, client-streaming and bidirectional RPCs. The service DSL uses `stream(MessageClass)` for streaming inputs and outputs. Controllers, middleware, errors, request IDs, rich error details and tracing use the same core API as Native.

## Concurrency and process lifecycle

Set `workers` above zero on Linux to fork multiple workers. With `inherited_fd`, the launcher owns one listening socket and passes it to fresh masters, which fork workers. A port of zero stays stable through worker replacement and `USR2`. `reuseport` is also supported, with the core's usual fixed-port requirement for multiple workers.

The adapter has one reactor thread per worker. `threads + max_waiting_requests` bounds concurrent RPC fibers; this is a capacity limit, not a pool of OS threads. Excess calls receive `RESOURCE_EXHAUSTED`. Use scheduler-aware I/O in handlers: blocking native drivers or CPU work stop progress for other RPCs on that worker.

Client cancellation and deadlines unwind scheduler-aware handlers. Graceful stop sends HTTP/2 GOAWAY, finishes accepted RPCs until `shutdown_timeout`, then closes outstanding connections. Admin `/livez`, `/readyz`, `/metrics` and `/status`, lifecycle hooks, worker resizing, phased restart and hot reexec remain available through the core supervisor.

Incoming frames, decompressed payloads, serialized replies and request metadata respect the configured size limits. Defaults are 4 MiB per message and 8 KiB of metadata.

## Initial release limits

Continuous-load phased restart recorded one UNAVAILABLE response; the zero-error target remains unmet. See the [accepted limitation and remedy](docs/adr/phased-restart-limit.md). This adapter remains outside the stable 1.0 support contract.

This experimental release serves plaintext HTTP/2 gRPC. TLS/mTLS, gRPC Health and Reflection are not implemented; TLS and Reflection configuration fails before binding. Use a TLS-terminating gRPC proxy and Gritz's HTTP readiness endpoint when needed.

Native connection-age and keepalive settings do not apply to this adapter. Their shared defaults remain unchanged; changing them raises a configuration error. `fork_mode :grpc_fork_support` and Native client factories require `gritz-native`. Async applications can use `Async::GRPC::Client` for outbound calls.

For Rails, select the Async transport before `rails_app`; gritz-rails 0.9.0 sets `ActiveSupport::IsolatedExecutionState.isolation_level = :fiber`. Use a scheduler-aware database driver and a suitable connection pool. gritz-otel 0.9.0 supports server tracing in isolated RPC fibers.

## Development

```sh
bundle install
COVERAGE=1 bundle exec rake
bundle exec rubocop
bundle exec bundler-audit check --update
bundle exec rake build
```

CI runs Ruby 3.3, 3.4 and 4.0. The shared `Gritz::Testing::TransportContract` uses the official grpc client solely as a development dependency, verifying all four RPC forms, metadata, errors, deadlines, cancellation and graceful shutdown. Tests also run a C-core-free cluster through worker kill, resizing, phased replacement and fresh master replacement. See the [validation report](docs/reports/async-validation.md) and [upstream integration decisions](docs/adr/async-transport.md).

`pkg/gritz-async.gem` is the strict-built release package. Publication uses the configured Trusted Publishing workflow. See [CONTRIBUTING.md](CONTRIBUTING.md) and the [release guide](docs/guides/releasing.md).

## Documentation

Read the [published guides and API reference](https://gritzrpc.github.io/gritz/), [public API policy](https://github.com/gritzrpc/gritz/blob/main/docs/public-api.md), [support policy](https://github.com/gritzrpc/gritz/blob/main/docs/support-policy.md) and [stabilization gate](https://github.com/gritzrpc/gritz/blob/main/docs/stabilization.md).

## License

[MIT](LICENSE.txt).

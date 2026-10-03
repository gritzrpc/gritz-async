# Async adapter validation

Date: 2026-10-03. Local environment: Linux ARM64, CRuby 3.4.11, Docker image `gritz-phase0-probe:local`. Upstream versions: async-grpc 0.10.0, async 2.46.0, async-http 0.105.0, protocol-grpc 0.17.0 and protocol-http2 0.29.1.

| Gem | Tests | Failures | Line coverage |
| --- | ---: | ---: | ---: |
| gritz-core 0.6.0 | 201 | 0 | 90.78% |
| gritz-native 0.6.0 | 124 | 0 | 97.94% |
| gritz 0.6.0 | 12 | 0 | 100% |
| gritz-otel 0.3.0 | 33 | 0 | 98.11% |
| gritz-rails 0.2.0 | 18 | 0 | 93.88% |
| gritz-async 0.1.0 | 33 | 0 | 97.73% |
| Total | 421 | 0 | — |

Each suite ran with `COVERAGE=1 bundle exec rspec`. Core excludes shared RSpec example definitions from its production coverage calculation; both adapters execute those definitions over real sockets. All six repositories passed RuboCop and `gem build --strict`. The combined dependency lock passed bundler-audit against ruby-advisory-db updated on 2026-10-02 (1,252 advisories).

Both Native and Async passed the same 14 TransportContract examples: four RPC forms, ordered output, output before half-close/controller completion, binary and repeated metadata, separate headers and trailers, rich error details, late streaming status, safe internal errors, unimplemented actions, deadline, cancellation, complete in-flight response during graceful shutdown and bounded forced shutdown.

Additional Async checks establish one reactor thread with isolated concurrent RPC fibers, overload rejection and final inflight cleanup, bounded wire and decompressed messages, outbound size and metadata limits, invalid compressed input rejection, early unary headers and cancellation cleanup that retains the client connection for another RPC. Pure service definitions and a fresh master boot without loading the official grpc extension. A runtime-only bundle contains 30 gems and excludes grpc, gritz-native and the gritz meta gem. An encoded HTTP/2 frame race checks HPACK synchronization for accepted-stream trailers during draining.

A real inherited-listener cluster ran two workers on one ephemeral port. It replaced a SIGKILLed worker, resized through three and two workers, replaced every worker with USR1 and started a fresh master with USR2. A separate request-count recycling check replaced a worker on the inherited ephemeral listener. The TCP port remained unchanged, retired generations were reaped and RPCs reached the new workers. Core independently verifies listener ownership across fresh generations and that the port is released at shutdown.

The included hello application's four methods also passed grpcurl 1.9.4: unary returned `Hello, Ruby`; server streaming returned `Ruby:0`, `Ruby:1`, `Ruby:2`; a two-message client stream returned count 2; bidi echoed both messages. The grpcurl release archive matched its upstream checksum. The caller used the supplied .proto file, without Reflection.

Rails overlapping executor fibers retained independent CurrentAttributes and reset state after completion. OpenTelemetry overlapping server fibers retained separate trace IDs and restored ambient context.

Existing main CI passed for Ruby 3.3 / 3.4 / 4.0: [core](https://github.com/gritzrpc/gritz-core/actions/runs/37080190809), [native](https://github.com/gritzrpc/gritz-native/actions/runs/37080277931), [meta](https://github.com/gritzrpc/gritz/actions/runs/37080323174), [otel](https://github.com/gritzrpc/gritz-otel/actions/runs/37080324304), [rails](https://github.com/gritzrpc/gritz-rails/actions/runs/37080326646). Rails includes both 8.0 and 8.1. [Async main CI](https://github.com/gritzrpc/gritz-async/actions/runs/37080984845) passed all three Ruby versions after the GOAWAY frame-race fix.

These initial results establish functional and lifecycle behavior. Subsequent Phase 6 work verified random worker kills, injected loopback latency and memory recycling on both adapters, and optimized suppressed completion logging in core 0.6.1. Full collection passed all five scenarios on both adapters, with 6,466,737 measured RPCs and no errors. A subsequent real CI baseline comparison passed for both adapters. Async CPU throughput scaled 1.815x from one to two workers; idle shutdown remained below the drain-delay-plus-one-second target. The [performance validation](https://github.com/gritzrpc/gritz-native/blob/main/docs/reports/performance-validation.md) retains all reports, exact locks, earlier failures and limitations. External beta operation was canceled by the owner.

The later continuous-load phased-restart gate returned one `UNAVAILABLE` in 3,001 calls. Its [restart-limit ADR](../adr/phased-restart-limit.md) records the failed target and remedy; the earlier in-flight contract does not supersede that result. The adapter remains experimental with the [documented initial limits](../adr/async-transport.md).

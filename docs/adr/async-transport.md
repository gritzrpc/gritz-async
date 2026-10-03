# Async transport integration

Status: accepted for the experimental 0.1.0 release.

Use async-grpc 0.10.x for dispatch, protocol-grpc 0.17.x for protobuf framing and metadata, async-http 0.105.x and protocol-http2 0.29.x for HTTP/2. The adapter adds core Call translation, resource limits and connection lifecycle ownership. It does not implement an independent HTTP/2 or protobuf parser.

All handlers run in child Async tasks, including unary handlers. This permits initial metadata and cancellation to progress while application I/O is pending. A response-body wrapper delays header transmission until metadata, the first reply or final status is ready. A stream reset stops the handler and closes its scope without writing response headers to a closed stream.

protocol-http2 0.29.1 `send_goaway` changes the connection state to closed immediately. async-http then stops its reader, losing accepted responses. The adapter's connection subclass sends a public GoawayFrame with the last accepted stream ID, keeps the reader active, ignores newer peer streams and closes after active streams finish or the deadline expires. The shared contract retains an in-flight unary handler during shutdown and asserts its complete response. This workaround can be removed when the upstream sender exposes equivalent graceful draining.

The launcher binds one stdlib Socket and passes duplicates to fresh masters over its existing UNIXSocket control channel. Workers inherit that socket before starting the reactor. The launcher never initializes Async or the official grpc extension. Owner, master and adapter each close only their owned handles. Reexec cannot change the bind address or listener strategy.

The initial adapter intentionally lacks TLS/mTLS, Reflection, gRPC Health, Native connection-age/keepalive tuning and a Gritz client factory. Unsupported explicit settings fail at bind time. Admin HTTP probes and metrics remain available. These features can follow verified demand; performance benchmarks, chaos scenarios and external beta operation remain pending and are not release-validation claims.

Primary implementation references: [async-grpc](https://github.com/socketry/async-grpc), [protocol-grpc](https://github.com/socketry/protocol-grpc), [async-http](https://github.com/socketry/async-http), [protocol-http2](https://github.com/socketry/protocol-http2).

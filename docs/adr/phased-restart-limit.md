# Async phased restart under persistent client load

- Status: Accepted
- Date: 2026-10-03

## Evidence

The 14 shared transport contracts pass, including completion of an already active RPC during shutdown. A separate Linux run used four inherited-listener workers, 64 ghz connections, 100 requests/s and 30 seconds of traffic while replacing every worker with USR1. All old and new workers received requests and the replacement completed in 0.927 seconds.

Of 3,001 calls, 3,000 succeeded and one failed with `Unavailable: the connection is draining` (0.0333%). The zero-error phased-restart target is **not met**. Retain the [failed report](https://github.com/gritzrpc/gritz-native/blob/main/bench/results/2026-10-03-async-phased-restart.json); do not replace it with the passing single-inflight contract result. Native completed 3,002 calls with zero errors in the corresponding run.

## Cause and remedy

The Async server sends one GOAWAY with the last stream it has received and closes connections after active streams finish. A request initiated concurrently with GOAWAY can encounter a draining client connection. The reported failure establishes the race at the client boundary; it does not establish which individual HTTP/2 frame arrived first.

Implement and verify a two-stage HTTP/2 graceful shutdown: announce GOAWAY with the maximum stream ID, use a PING acknowledgement to establish a round trip, then advertise the final accepted stream ID and await accepted streams within the shutdown deadline. Add an encoded-frame regression and repeat the concurrent ghz restart gate without masking failures with application retries. Preserve bounded forced shutdown and HPACK state handling.

## Decision

Keep Async experimental. It must not claim zero-error phased restart or graduate into the stable support contract until that remedy passes the live-load gate. Native remains the default adapter. This records an unmet Phase 6 target and its corrective work, as allowed by the roadmap; functional contract success alone is not sufficient to promote Async.

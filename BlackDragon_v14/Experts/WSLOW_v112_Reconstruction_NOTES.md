# WSLOW v1.12 reconstruction

Authorized behavioral reconstruction of `WSLOW public v1.12.ex5`.

Original artifact authority:
- SHA256 `68e5f04634fa211cadabd6cab73f23a9727daf1f3805bfc598071a76c880684a`
- bytes `49242`
- TIP026 binary ref `BIN-180ba96604dd66991ebdce2ebe665b39ca68e34de9a3a69180b0cd39a4af146b`

Evidence-locked modules in `WSLOW_v112_Reconstructed.mq5`:
- observed input surface
- M15 decision cadence
- P1/P2/base then geometric recovery sizing
- P1-anchored cumulative grid levels
- weighted basket TP formula
- shared P1-anchored emergency SL in observed configuration
- CTrade market execution

`SignalCore()` is intentionally isolated and marked as a reconstructed proxy. Exact original signal math requires runtime memory/process tracing evidence not exposed by the current TIP026 tool catalog.

# BlackDragon v15.04 / T17.27 — GitHub composite build

Build entry: `BlackDragon_v14/Experts/BlackDragon/BlackDragon.mq5`.

This branch materializes the latest T17.27 production delta on top of the verified T17.26 incident-fix baseline, preserving the demonstrated `TimeCurrent()+1` protective-history horizon and bounded `PROTECTIVE_MISMATCH` diagnostics. It also carries the native MetaEditor compatibility edits required for zero-warning compilation: the T17.27 unit-policy legacy selector is unconditional fail-closed at revision 2, and NewsCalendar long-to-datetime conversions are explicit.

Transport is SHA-256-attested before apply. Native Windows compilation is a separate workflow and is the release gate before merge.

# Offline build review — 2026-09-20

Confirmed from original reports and hashes: attempt-1 meets40MHz timing (WNS0.779ns, TNS0; WHS0.024ns, THS0; failing endpoints0), uses13777 LUTs, and generated bitstream SHA256 2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52. Input and tooling checksum lists independently verify. No independent Vivado rerun or new board execution this review.

Recognize successful offline implementation metrics, not blanket board-ready approval. Finish the four explicit reviewer attestations from original constraints/strategy/methodology/DRC details in the next preflight package; matching warning names/counts alone does not prove unchanged affected circuitry. No clock reduction or CPU optimization is required merely because positive slack is small.

Corrections for the next handoff:
- Register file total3205 LUTs is NOT3205 LUTRAMs. Hierarchical utilization reports3117 logic LUTs and88 LUTRAMs, FF0. Keep those distinctions.
- BOARD-PROCEDURE uses native-endian `od -tx4` on big-endian device-tree cells; its expected numeric output is not portable to the little-endian ARM. Parse bytes as big endian with actual #address-cells/#size-cells and all tuples, then check interval overlap. A listing of reserved-memory children cannot establish their address ranges.
- Bind live-memory preflight to the SAME boot session used for loading. Current sequence checks memory and then cold power-cycles; re-check after the final reboot before programming/loading. Do not prescribe OS/SD/device-tree changes if it fails.
- Board transport is not yet implemented; ARM executable was linked, not executed. Late-recovery22-case result is archived evidence here, not independently rerun this turn.

Proceed with offline board-runner/preflight package. Hardware access/programming remains separately authorized, PL_RECONFIG_SAFE0 and cold-only recovery unchanged.

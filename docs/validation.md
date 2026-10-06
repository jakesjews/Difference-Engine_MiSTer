# Validation — 5 October 2026

Tested release: [`DifferenceEngine_20261005.rbf`](../releases/DifferenceEngine_20261005.rbf).

```text
SHA-256: 1d0a11e85324816cd1d770fe0545b3d1a6d7e89a813fd11b2d5c1731041abc5b
```

The release file was copied back from `/media/fat/_Computer/DifferenceEngine.rbf` on the MiSTer after testing, and its SHA-256 was checked against the tested bitstream. It was not rebuilt for publication. The release includes the simplified panel. README images are captures from that running FPGA.

## Simulation

`make test` passed on the final RTL:

- 8,410 arithmetic load/phase vectors and 2,040 complete cycles, including 200 randomized full-width states, signed polynomials of degrees zero through seven, carry cascades, and complement wraparound.
- Polynomial table generation, printer ordering and ring wrap, keyboard/gamepad controls, wheel editing, pause, reset, help, malformed files, and atomic loading.
- The actual unchanged MiSTer `hps_io`: status writes, PS/2 make/break sequences, file downloads, and index filtering.
- 640×480 active pixels, 800×525 total timing, 96-pixel horizontal sync, two-line vertical sync, pixel enables, blanking, and continuous video through machine reset.

Local evidence: `build/ui-cleanup-test.log`.

## Quartus

Quartus Prime Lite 17.0.2 Build 602, running through CrossOver, completed synthesis, fitting, assembly, and timing for the Cyclone V 5CSEBA6U23I7.

The complete MiSTer design uses 13,037 ALMs (31%), 18,484 registers, 57 RAM blocks, 33 DSP blocks, and three PLLs. These counts include the standard framework.

All four operating corners pass. Values below are worst slack in nanoseconds:

| Corner | Setup | Hold | Recovery | Removal |
| --- | ---: | ---: | ---: | ---: |
| Slow 1100mV 100C Model | 0.548 | 0.253 | 4.286 | 0.882 |
| Slow 1100mV -40C Model | 0.270 | 0.117 | 4.356 | 0.796 |
| Fast 1100mV 100C Model | 3.226 | 0.135 | 5.210 | 0.438 |
| Fast 1100mV -40C Model | 3.830 | 0.074 | 5.465 | 0.347 |

There are no illegal or unconstrained clocks. The inherited framework constraints leave four input ports and fifty output ports without external delay constraints; this result is not a measurement of external signal integrity. No framework timing exceptions or source files were changed.

Local evidence: `build/quartus-compile.log`, `build/timing-report.log`, `build/timing-corners.tsv`, `build/critical-paths.rpt`, `build/hold-paths.rpt`, and `build/unconstrained-paths.rpt`.

## MiSTer

The final bitstream was loaded and exercised through Zaparoo keyboard/gamepad input. Screenshots were decoded using the core's font, checking all 248 wheel digits and the cycle counter against independent integer polynomial calculations.

- Museum polynomial: twelve completed cycles, with all eight columns correct.
- Custom file: `3x³ − 2x + 7`, starting at x=10; correct initial state and twelve subsequent cycles.
- Invalid file: the error appears in the footer and all columns and the cycle counter remain unchanged. A subsequent valid file clears the error.
- Automatic operation: 996 completed cycles, all eight columns correct, and all sixteen printed rows matching their expected values.
- Help pauses an automatic run; two captures taken two seconds apart were pixel-identical. Closing help resumes it.
- Gamepad crank and run/pause work. Wheel increment/decrement were also checked during initial hardware bring-up with the same controls RTL.
- The README carry recipe shows the pending carry, resolves all 31 digits to zero, and completes the cycle. Its manual counting recipe produces 10, 13, 16, 19.

Normal scaled output was checked with 1280×960 captures using a temporary `direct_video=0` override. The original INI was then restored byte for byte, the core reloaded with `direct_video=1`, and the user confirmed the direct-video display works well. Physical signal quality was not instrumented.

The temporary Zaparoo controller map and two test tables were removed. The eight supplied demonstration tables remain installed. The user's existing Zaparoo service was left available.

Local evidence: `build/hardware/final-checks.log`, `build/hardware/checks.jsonl`, numbered PNG captures, and `build/hardware/cleanup.txt`.

`make framework-check` confirms every tracked `sys/` file still matches baseline `5cd115fdb8f73d636713f4b2d51b2df664e5b865`.

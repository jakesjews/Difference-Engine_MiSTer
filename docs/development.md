# Development

The Quartus project is `DifferenceEngine.qpf`. The MiSTer framework under `sys/` must remain unchanged. The calculating section, controls, loader, printer, and renderer live in `rtl/de2_*.sv`; `DifferenceEngine.sv` supplies the MiSTer interface. See [architecture.md](architecture.md) for arithmetic, timing, and historical references.

## Simulation

Requires Verilator, Icarus Verilog, Python 3, a C++ compiler, Make, and SDL2 (`sdl2-config`). Yosys is needed for generic synthesis.

```sh
make test
make sim
make screenshots
make synth
make framework-check
```

`make test` checks 8,410 independently generated arithmetic load/phase vectors, 2,040 complete cycles, 200 random full-width states, signed polynomials of degrees zero through seven, decimal carries, and complement wraparound. It also exercises the printer ring, controls, editing, malformed files and atomic loading, raster geometry, reset, and the actual unchanged `hps_io` status/PS2/file protocol.

The desktop simulator uses the core's keyboard controls, with F7 to change speed. Drop a `.de2` file onto its window to load a table. It runs as fast as the host permits, so it is not a real-time performance measurement. Close the window to stop it.

The HPS harness uses `-Wno-PROCASSWIRE` for the upstream constant-pruned `PS2DIV=0` branch. Other framework compatibility warnings are retained in `build/mister-build.log`; no framework source patch is applied. `make framework-check` compares `sys/` with baseline `5cd115fdb8f73d636713f4b2d51b2df664e5b865`.

## Quartus through CrossOver

```sh
./build.sh map
./build.sh compile
```

The helper defaults to the installed Quartus 17.0 CrossOver bottle. Override `CROSSOVER_BIN`, `QUARTUS_BOTTLE`, or `QUARTUS_BIN` when needed. The output is `output_files/DifferenceEngine.rbf`.

A full compile includes fitting, assembly, and all four timing corners. `tools/report_timing.tcl` checks setup, hold, recovery, and removal, and fails on negative slack. Reports are saved under `build/`. Successful synthesis alone does not validate fit, timing, or physical operation.

## MiSTer checks

`sim/mister_capture.py` uses a running Zaparoo service to send optional input and save actual FPGA screenshots. It calls Zaparoo's local CLI over SSH by default; `--transport http` uses its HTTP API when that is permitted by the device's access settings:

```sh
uv run sim/mister_capture.py build/hardware/ready.png --read-panel
uv run sim/mister_capture.py build/hardware/crank.png --keys '{f2}' --settle 7 --read-panel
```

The reader decodes all 248 displayed wheels and the cycle counter. Direct video must be off for a complete capture. Keep any diagnostic configuration changes temporary and restore the user's configuration afterward. Screenshot capture does not validate a physical display or analog signal quality.

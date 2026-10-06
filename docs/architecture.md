# Arithmetic and implementation notes

This core implements the calculating section of **Difference Engine No. 2** at the decimal-register level. The capacity is eight 31-digit decimal columns: the tabular value T and differences D1 through D7. It is an addition machine, not the instruction-programmed Analytical Engine.

## Calculating cycle

The primary reference is Doron Swade's [*Difference Engine No. 2: Technical Description*](https://www.sciencemuseum.org.uk/sites/default/files/2023-09/DE2_Technical_Description.pdf), chapter 3, especially pp. 19–21 and 45–46. The core splits its calculation into four observable stages:

1. Add D1 into T, D3 into D2, D5 into D4, and D7 into D6. Each decimal wheel wraps individually; a carry warning is latched wherever the sum reaches ten.
2. Resolve warnings on T, D2, D4, and D6, from units upwards, propagating cascaded carries.
3. Add D2 into D1, D4 into D3, and D6 into D5, again latching warnings.
4. Resolve warnings on D1, D3, and D5. Mark the complete cycle and append the result to the paper history.

All active pairs operate concurrently. The hardware services one decimal position per 50 MHz clock, taking 31 clocks for each stage. The seventh difference is never altered. At each complete-cycle boundary the state agrees with the staggered difference table.

If `f(x)` is the polynomial and `n` the argument of the currently displayed result, column `i` holds:

```text
C[i] = forward_difference^i f(n - floor(i/2)) modulo 10^31
```

This differs from loading every forward difference at the same argument. For example, `x^3` at zero requires `[0, 1, 0, 6, 0, 0, 0, 0]`. The museum's polynomial `8x^7 + 2x^6 + 9x^5 + 5x^4 + x^3 + 7x^2 + 4x + 41` requires `[41, 36, 28, 1464, 360, 15240, 1440, 40320]`. That table matches the [*User Manual*](https://www.sciencemuseum.org.uk/sites/default/files/2023-08/User_Manual_PDF_Vsn_1.1_Final_SEC1.pdf), p. 21.

Negative numbers are represented by 31-digit ten's complements. Arithmetic wraps modulo `10^31`; final carries are shown separately and are **not** treated as errors, since they also occur during legitimate complement arithmetic. Thus the descending preset continues from zero to `999...999` (minus one).

## Fidelity boundary

The four stages are logical operations, not a model of all fifty chapter-disc timing positions. Giving-off preserves the source value, making restoration implicit; physical wheels are not individually driven to zero and restored. Cam geometry, backlash, interlocks, mechanical jams, disconnected carry levers, physical setting-up procedures, stereotyping, and programmable print layout are not modeled.

The original output mechanism transfers only the lower thirty digits (User Manual p. 11). The on-screen paper does the same; all thirty-one remain visible on the wheels. The paper stores the latest sixteen entries, including the initial value after loading or editing. Its four-digit STEP field is the count of completed cycles modulo 10,000; the six-digit counter beneath the wheels wraps at 1,000,000. These are UI counters separate from the figure wheels. For a file generated with a nonzero starting argument, `x = start + completed_cycles`; the file itself does not encode that starting argument.

Run/pause stops between logical stages, after any active 31-clock stage finishes. Edits are enabled only when stopped at a full-cycle boundary. F2 completes the current cycle, including when starting from a partial one. F3 advances exactly one stage. Opening the OSD or help pauses automatic progress, retaining the run switch; closing it resumes. The speed controls set nominal steady-state rates; arithmetic itself always executes at 50 MHz.

## Modules and platform boundary

| Module | Responsibility |
| --- | --- |
| `de2_engine` | BCD registers, giving-off, warning latches, carry propagation, cycle count |
| `de2_loader` | Ordered, exact-size ASCII table validation; atomic load on completion |
| `de2_presets` | Eight initial tables |
| `de2_controls` | Decoded PS/2 events, repeat suppression for actions, gamepad edges, wheel cursor |
| `de2_printer` | Sixteen-row circular print history |
| `de2_font`, `de2_video` | Original procedural front panel and 640x480 RGB raster |
| `difference_engine` | Operating controls, phase timing, module integration |
| `de2_pll` | 50 MHz PLL clock required by the framework's video clock mux |
| `DifferenceEngine.sv` | MiSTer `emu` interface, OSD, unchanged `hps_io`, unused-port defaults |

The wrapper derives a 50 MHz core clock from the native 50 MHz input using a PLL, as required by MiSTer's video clock mux. Pixel enable divides it by two; the output is 640x480 with 800x525 total pixels, 96-pixel negative horizontal sync and two-line negative vertical sync, approximately 59.524 Hz. The renderer scans the wheel and paper grids with counters, uses bounded unsigned coordinates for text, and registers the selected glyph and colors before font lookup. DE and sync traverse the same two stages, keeping every pixel aligned. The raster is intentionally not reset by a machine reset. Loss of PLL lock holds the calculating section in reset until the clock is stable. No external SDRAM, DDR3, ROM image, or CPU is required. Audio is silent.

The `sys/` framework matches repository baseline `5cd115fdb8f73d636713f4b2d51b2df664e5b865`. The template PLL sources remain untouched and unused by the core. No renderer or CPU RTL was copied from the reference cores.

## UI references inspected

| Reference | Revision | Inspiration |
| --- | --- | --- |
| [PDP-1](https://github.com/MiSTer-devel/PDP1_MiSTer) | `b8059feb429dd4a3b87c538e677b8caadef4c99b` | Visible machine state, illuminated indicators, selected front-panel control |
| [Altair 8800](https://github.com/MiSTer-devel/Altair8800_Mister) | `a142e9f74b73094c13adca8b9b7d476a3f18d449` | Arrow-key selection and direct panel operation |
| [EDSAC](https://github.com/MiSTer-devel/EDSAC_MiSTer) | `b076a3c5a42f71ac2e43f67bd52ee03221a373d1` | Educational machine visualization and scrolling printed results |

Downloaded research copies live in ignored `build/research/`; they are not build inputs. All panel graphics and the small bitmap alphabet are generated by original RTL.

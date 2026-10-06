PYTHON ?= python3
VERILATOR ?= verilator
IVERILOG ?= iverilog
VVP ?= vvp
YOSYS ?= yosys

RTL := rtl/de2_engine.sv rtl/de2_loader.sv rtl/de2_controls.sv rtl/de2_presets.sv \
       rtl/de2_printer.sv rtl/de2_font.sv rtl/de2_video.sv rtl/difference_engine.sv
# FPGA power-up values and explicitly unused output ports are intentional.
VFLAGS := -Wall -Wno-PROCASSINIT -Wno-PINCONNECTEMPTY

.PHONY: test lint test-engine test-tables test-printer test-mister sim screenshots synth framework-check clean

test: lint test-tables test-engine test-printer test-mister build/sim/de2_sim
	build/sim/de2_sim --test
	$(MAKE) framework-check

lint:
	$(VERILATOR) --lint-only $(VFLAGS) --top-module difference_engine $(RTL)

test-tables:
	$(PYTHON) sim/test_tables.py

test-engine:
	@mkdir -p build
	$(PYTHON) sim/generate_vectors.py
	$(IVERILOG) -g2012 -s tb_engine -o build/tb_engine rtl/de2_engine.sv sim/tb_engine.sv
	$(VVP) build/tb_engine

test-printer:
	@mkdir -p build
	$(IVERILOG) -g2012 -s tb_printer -o build/tb_printer rtl/de2_printer.sv sim/tb_printer.sv
	$(VVP) build/tb_printer

# hps_io references PS2DIV=0's absent serial-PS/2 registers in constant-false
# procedural branches. Allow Verilator to prune those branches without editing
# the framework. Its other compatibility warnings remain in the build log.
test-mister:
	@mkdir -p build/mister
	$(VERILATOR) --binary --timing -j 4 -Wno-fatal -Wno-PINMISSING -Wno-PROCASSWIRE -Isim -I. \
		--top-module tb_emu --Mdir build/mister -o tb_emu \
		$(RTL) sim/de2_pll.sv DifferenceEngine.sv sys/hps_io.sv sim/tb_emu.sv > build/mister-build.log 2>&1
	build/mister/tb_emu

build/sim/de2_sim: $(RTL) sim/main.cpp
	@mkdir -p build/sim
	$(VERILATOR) --cc --exe --build -j 4 $(VFLAGS) --top-module difference_engine \
		--Mdir build/sim -o de2_sim -CFLAGS "-std=c++17 $$(sdl2-config --cflags)" \
		-LDFLAGS "$$(sdl2-config --libs)" $(RTL) $(CURDIR)/sim/main.cpp

sim: build/sim/de2_sim
	build/sim/de2_sim --interactive

screenshots: build/sim/de2_sim
	@mkdir -p build/screenshots
	build/sim/de2_sim --screenshots build/screenshots

# Portable logic estimate only: no Quartus, fitter, vendor timing or board access.
synth:
	@mkdir -p build
	$(YOSYS) -Q -T -l build/synthesis.log -p 'read_verilog -sv $(RTL); hierarchy -check -top difference_engine; synth -top difference_engine; check; stat' > build/synthesis-console.log
	@tail -30 build/synthesis.log

framework-check:
	@git diff --exit-code 5cd115fdb8f73d636713f4b2d51b2df664e5b865 -- sys
	@echo "MiSTer sys/ matches the initial template commit."

clean:
	rm -rf build/sim build/mister build/tb_engine build/tb_printer build/engine-vectors.txt build/screenshots

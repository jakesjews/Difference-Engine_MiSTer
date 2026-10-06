`timescale 1ns/1ps
module tb_engine;
reg clk = 0;
always #5 clk = ~clk;
reg reset = 1;
reg load = 0;
reg advance = 0;
reg edit = 0;
reg [991:0] load_columns = 0;
reg [2:0] edit_column = 0;
reg [4:0] edit_digit = 0;
reg [3:0] edit_value = 0;
wire [991:0] columns;
wire [247:0] warnings;
wire [7:0] carry_out;
wire [1:0] phase;
wire [4:0] digit;
wire busy, result_valid;
wire [23:0] count;
de2_engine dut (.*);

task tick;
	begin @(posedge clk); #1; end
endtask
task launch;
	begin
		@(negedge clk); advance = 1;
		tick();
		@(negedge clk); advance = 0;
	end
endtask

integer file, fields, operation, expected_phase, line = 0, timeout, pulses = 0;
reg [991:0] expected;
reg [247:0] expected_warnings;
reg [7:0] expected_carry;
reg [23:0] expected_count;
initial begin
	tick(); tick();
	@(negedge clk); reset = 0;
	file = $fopen("build/engine-vectors.txt", "r");
	if(!file) $fatal(1, "Missing vectors; run sim/generate_vectors.py");
	while(!$feof(file)) begin
		fields = $fscanf(file, "%d %h %h %h %d %h\n", operation, expected, expected_warnings,
			expected_carry, expected_phase, expected_count);
		if(fields != 6) $fatal(1, "Malformed vector %0d", line);
		line = line + 1;
		if(operation == 0) begin
			@(negedge clk); load_columns = expected; load = 1;
			tick();
			@(negedge clk); load = 0;
		end else begin
			launch();
			timeout = 0;
			while(busy && timeout < 40) begin tick(); timeout = timeout + 1; end
			if(timeout != 31) $fatal(1, "Phase duration %0d != 31", timeout);
			if(result_valid != (expected_phase == 0)) $fatal(1, "Result strobe at wrong phase");
			if(result_valid) pulses = pulses + 1;
		end
		if(columns !== expected || warnings !== expected_warnings || carry_out !== expected_carry ||
			phase !== expected_phase[1:0] || count !== expected_count)
			$fatal(1, "Vector %0d mismatch phase=%0d carry=%h/%h count=%h/%h\ncolumns=%h\nexpect =%h\nwarn=%h/%h",
				line, phase, carry_out, expected_carry, count, expected_count, columns, expected, warnings, expected_warnings);
	end
	$fclose(file);

	// Edits, invalid digits, edits during a cycle, load/reset while busy.
	@(negedge clk); load = 1; load_columns = 0;
	tick();
	@(negedge clk); load = 0; edit = 1; edit_column = 7; edit_digit = 30; edit_value = 9;
	tick();
	if(columns[991:988] !== 9) $fatal(1,"Top wheel edit failed");
	@(negedge clk); edit_digit = 31; edit_value = 2;
	tick();
	if(columns !== (992'h9 << 988)) $fatal(1,"Out-of-range wheel changed machine");
	@(negedge clk); edit_digit = 30; edit_value = 15;
	tick();
	if(columns[991:988] !== 9) $fatal(1,"Invalid BCD digit accepted");
	@(negedge clk); edit = 0;
	launch();
	while(busy) tick();
	@(negedge clk); edit = 1; edit_value = 1;
	tick();
	if(columns[991:988] !== 9) $fatal(1,"Edit accepted mid-cycle");
	@(negedge clk); edit = 0;
	launch();
	@(negedge clk); reset = 1;
	tick();
	if(columns !== 0 || busy || phase != 0 || warnings != 0 || count != 0 || result_valid)
		$fatal(1,"Mid-phase reset failed");
	@(negedge clk); reset = 0;
	launch();
	@(negedge clk); load = 1; load_columns = 992'h42;
	tick();
	if(columns !== 992'h42 || busy || phase != 0 || warnings != 0)
		$fatal(1,"Mid-phase load failed");
	$display("PASS engine: %0d vectors, %0d completed cycles; edit guards, reset and load", line, pulses);
	$finish;
end
initial begin #10000000; $fatal(1,"Simulation timeout"); end
endmodule

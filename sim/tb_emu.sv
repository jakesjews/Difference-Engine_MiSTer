`timescale 1ns/1ps
// Exercise the actual unmodified hps_io, including MiSTer's file protocol.
module tb_emu;
reg clk = 0;
reg clk100 = 0;
always #10 clk = !clk;
always #5 clk100 = !clk100;
reg reset = 1;
reg osd = 0;
tri [45:0] bus;
reg [15:0] hps_word = 0;
reg strobe = 0, io_enable = 0, file_enable = 0;
wire hs, vs, de, ce;
assign bus[31:16] = hps_word;
assign bus[35:33] = {file_enable,io_enable,strobe};
assign bus[45:38] = {1'b0,vs,clk100,clk,ce,de,hs,vs};

emu dut (
	.CLK_50M(clk), .RESET(reset), .OSD_STATUS(osd), .HPS_BUS(bus),
	.VGA_HS(hs), .VGA_VS(vs), .VGA_DE(de), .CE_PIXEL(ce)
);

task tick;
	begin @(posedge clk); #1; end
endtask
task word(input [15:0] value);
	begin
		@(negedge clk); hps_word = value; strobe = 1;
		tick();
		@(negedge clk); strobe = 0;
		repeat(4) tick();
	end
endtask
task start(input bit file_transfer, input [15:0] command);
	begin
		@(negedge clk); file_enable = file_transfer; io_enable = !file_transfer;
		word(command);
	end
endtask
task stop;
	begin
		@(negedge clk); file_enable = 0; io_enable = 0;
		repeat(8) tick();
	end
endtask
task status_word(input [15:0] value);
	begin
		start(0,16'h1e); word(value);
		repeat(7) word(0);
		stop();
	end
endtask
task keyboard(input [7:0] code, input bit pressed);
	begin
		start(0,16'h05);
		if(!pressed) word(16'hf0);
		word({8'd0,code}); stop();
	end
endtask

integer c, d;
reg [7:0] digit;
initial begin
	repeat(10) tick();
	if(dut.pll_locked || !dut.reset_sync[1]) $fatal(1,"Engine released before PLL lock");
	// The HPS initializes cfg, joysticks and status before releasing reset.
	start(0,16'h01); word(0); stop();
	start(0,16'h02); word(0); word(0); stop();
	status_word(16'h00c4); // Squares, 60 results/sec.
	@(negedge clk); reset = 0;
	repeat(20) tick();
	if(!dut.pll_locked || dut.reset_sync[1]) $fatal(1,"Engine did not leave reset after PLL lock");
	if(dut.core.columns[123:0] != 0 || dut.core.columns[247:124] != 1 || dut.core.columns[371:248] != 2)
		$fatal(1,"HPS status did not select squares");
	keyboard(8'h04,1); keyboard(8'h04,0); // F3: actual PS/2 bytes -> decoded event -> phase.
	repeat(40) tick();
	if(dut.core.phase != 1 || dut.core.columns[123:0] != 1) $fatal(1,"HPS keyboard phase step failed");
	keyboard(8'h03,1); keyboard(8'h03,0); // F5.
	if(dut.core.phase != 0 || dut.core.columns[123:0] != 0) $fatal(1,"HPS keyboard reload failed");
	// File index 1 matches F1 in the core's CONF_STR.
	start(1,16'h55); word(1); stop();
	start(1,16'h53); word(1); stop();
	if(!dut.core.downloading) $fatal(1,"HPS download start not propagated");
	start(1,16'h54);
	for(c=0;c<8;c=c+1) begin
		for(d=30;d>=0;d=d-1) begin
			digit = (d==0 && c==0) ? 8'h37 : (d==0 && c==1) ? 8'h33 : 8'h30;
			word({8'd0,digit});
		end
		word(16'h0a);
	end
	stop();
	start(1,16'h53); word(0); stop();
	if(dut.core.load_error || dut.core.columns[123:0] != 7 || dut.core.columns[247:124] != 3)
		$fatal(1,"Real HPS file transaction failed, error=%b T=%h D1=%h",dut.core.load_error,
			dut.core.columns[123:0],dut.core.columns[247:124]);
	// Other file indices are ignored.
	start(1,16'h55); word(2); stop();
	start(1,16'h53); word(1); stop();
	start(1,16'h54); word(16'h39); stop();
	start(1,16'h53); word(0); stop();
	if(dut.core.columns[123:0] != 7 || dut.core.load_error) $fatal(1,"Unrelated ioctl index changed machine");
	$display("PASS MiSTer wrapper: real hps_io status, PS/2 make/break, file download and index filtering");
	$finish;
end
initial begin #1000000; $fatal(1,"HPS protocol test timeout"); end
endmodule

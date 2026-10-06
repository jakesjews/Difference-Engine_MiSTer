`timescale 1ns/1ps
module tb_printer;
reg clk = 0;
always #5 clk = !clk;
reg clear = 1, write = 0;
reg [119:0] value = 0;
reg [15:0] count = 0;
reg [3:0] read_age = 0;
wire [119:0] read_value;
wire [15:0] read_count;
wire read_valid;
de2_printer dut (.*);
integer n, age;
initial begin
	@(posedge clk); #1;
	if(read_valid) $fatal(1,"Cleared printer reports valid rows");
	@(negedge clk); clear=0;
	for(n=0;n<37;n=n+1) begin
		write=1; value=120'(n*17); count=16'(n);
		@(posedge clk); #1;
		@(negedge clk); write=0;
		for(age=0;age<16;age=age+1) begin
			read_age=4'(age); #1;
			if(read_valid != (age<=n)) $fatal(1,"Incorrect row validity");
			if(read_valid && (read_value != (n-age)*17 || read_count != n-age))
				$fatal(1,"Incorrect printer order after row %0d age %0d",n,age);
		end
		@(negedge clk);
	end
	clear=1; write=1;
	@(posedge clk); #1;
	if(read_valid) $fatal(1,"Clear must take priority over print");
	$display("PASS printer: chronological reads, validity, repeated ring wrap, clear/write priority");
	$finish;
end
endmodule

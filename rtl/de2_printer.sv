// SPDX-License-Identifier: GPL-2.0-or-later
// Last sixteen tabulations. The physical printer transferred only 30 digits.
module de2_printer (
	input  wire         clk,
	input  wire         clear,
	input  wire         write,
	input  wire [119:0] value,
	input  wire [15:0]  count,
	input  wire [3:0]   read_age,
	output wire [119:0] read_value,
	output wire [15:0]  read_count,
	output wire         read_valid
);
reg [119:0] paper [0:15];
reg [15:0] numbers [0:15];
reg [3:0] head;
reg [4:0] used;
wire [3:0] address = head - 1'b1 - read_age;
assign read_value = paper[address];
assign read_count = numbers[address];
assign read_valid = {1'b0, read_age} < used;

always @(posedge clk) begin
	if(clear) begin
		head <= 0;
		used <= 0;
	end else if(write) begin
		paper[head] <= value;
		numbers[head] <= count;
		head <= head + 1'b1;
		if(used < 16) used <= used + 1'b1;
	end
end
endmodule

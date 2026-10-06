// SPDX-License-Identifier: GPL-2.0-or-later
// Difference Engine No. 2: 8 columns, 31 decimal wheels per column.
// The four phases are odd giving-off, even carry, even giving-off, odd carry.
// Source restoration is implicit: giving-off preserves the source register.
module de2_engine (
	input  wire         clk,
	input  wire         reset,
	input  wire         load,
	input  wire [991:0]  load_columns,
	input  wire         advance,
	input  wire         edit,
	input  wire [2:0]   edit_column,
	input  wire [4:0]   edit_digit,
	input  wire [3:0]   edit_value,
	output wire [991:0] columns,
	output wire [247:0] warnings,
	output reg  [7:0]   carry_out,
	output reg  [1:0]   phase,
	output reg  [4:0]   digit,
	output reg          busy,
	output reg          result_valid,
	output reg  [23:0]  count
);

reg [123:0] wheel [0:7];
reg [30:0] warning [0:7];
reg [6:0] carry;
wire [4:0] sum [0:6];

genvar c;
generate
	for(c = 0; c < 8; c = c + 1) begin : column_bus
		assign columns[c*124 +: 124] = wheel[c];
		assign warnings[c*31 +: 31] = warning[c];
	end
	for(c = 0; c < 7; c = c + 1) begin : decimal_adder
		assign sum[c] = {1'b0, wheel[c][digit*4 +: 4]} +
			(phase[0] ? {4'b0, carry[c]} : {1'b0, wheel[c+1][digit*4 +: 4]});
	end
endgenerate

function automatic [23:0] increment_count(input [23:0] value);
	integer n;
	reg propagate;
	begin
		increment_count = value;
		propagate = 1;
		for(n = 0; n < 6; n = n + 1) begin
			if(propagate) begin
				if(value[n*4 +: 4] == 9) increment_count[n*4 +: 4] = 0;
				else begin
					increment_count[n*4 +: 4] = value[n*4 +: 4] + 1'b1;
					propagate = 0;
				end
			end
		end
	end
endfunction

integer i;
always @(posedge clk) begin
	result_valid <= 0;
	if(reset || load) begin
		for(i = 0; i < 8; i = i + 1) begin
			wheel[i] <= reset ? 124'd0 : load_columns[i*124 +: 124];
			warning[i] <= 0;
		end
		carry <= 0;
		carry_out <= 0;
		phase <= 0;
		digit <= 0;
		busy <= 0;
		count <= 0;
	end else if(busy) begin
		// All four (or three) column pairs operate concurrently. Decimal
		// positions are serviced bottom-to-top, including chained carries.
		for(i = 0; i < 7; i = i + 1) begin
			if((i % 2) == int'(phase[1])) begin
				wheel[i][digit*4 +: 4] <= 4'((sum[i] >= 10) ? sum[i] - 5'd10 : sum[i]);
				if(!phase[0]) warning[i][digit] <= sum[i] >= 10;
				else begin
					carry[i] <= warning[i][digit] | (sum[i] >= 10);
					warning[i][digit] <= 0;
					if(digit == 30) carry_out[i] <= warning[i][digit] | (sum[i] >= 10);
				end
			end
		end
		if(digit == 30) begin
			busy <= 0;
			digit <= 0;
			phase <= phase + 1'b1;
			if(phase == 3) begin
				result_valid <= 1;
				count <= increment_count(count);
			end
		end else digit <= digit + 1'b1;
	end else if(advance) begin
		busy <= 1;
		digit <= 0;
		carry <= 0;
		if(phase == 0) carry_out <= 0;
	end else if(edit && phase == 0 && edit_digit < 31 && edit_value < 10) begin
		wheel[edit_column][edit_digit*4 +: 4] <= edit_value;
		carry_out <= 0;
		count <= 0;
	end
end

endmodule

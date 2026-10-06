// SPDX-License-Identifier: GPL-2.0-or-later
// .de2: eight lines (T,D1,...,D7), each 31 ASCII digits followed by LF.
// Atomic load: a malformed/truncated download never changes the engine.
module de2_loader (
	input  wire         clk,
	input  wire         reset,
	input  wire         downloading,
	input  wire         wr,
	input  wire [26:0]  address,
	input  wire [7:0]   data,
	output reg  [991:0] columns,
	output reg          valid,
	output reg          error
);

reg active;
reg bad;
reg [8:0] received;
wire legal = address < 256 && address == {18'd0, received} &&
	((address[4:0] == 31) ? data == 8'h0a : (data >= "0" && data <= "9"));

always @(posedge clk) begin
	valid <= 0;
	active <= downloading;
	if(reset) begin
		active <= 0;
		bad <= 0;
		error <= 0;
		received <= 0;
		columns <= 0;
	end else begin
		if(downloading && !active) begin
			received <= 0;
			bad <= 0;
			error <= 0;
		end
		if(downloading && wr) begin
			// HPS normally asserts download before wr; accept a first byte
			// arriving on the start edge as well.
			if((!active && address == 0 && data >= "0" && data <= "9") || (active && legal)) begin
				if(address[4:0] != 31)
					columns[int'(address[7:5])*124 + (30-int'(address[4:0]))*4 +: 4] <= data[3:0];
				received <= active ? received + 1'b1 : 9'd1;
			end else bad <= 1;
		end
		if(!downloading && active) begin
			valid <= !bad && received == 256;
			error <= bad || received != 256;
		end
	end
end

endmodule

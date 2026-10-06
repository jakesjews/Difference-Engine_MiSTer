// SPDX-License-Identifier: GPL-2.0-or-later
// Start at x=0. Values match tools/make_de2.py; D_i = delta^i f(-floor(i/2)).
module de2_presets (
	input  wire [2:0]   preset,
	output reg  [991:0] columns
);
always @* begin
	columns = 0;
	case(preset)
		0: begin // Science Museum demonstration polynomial, User Manual p.21.
			columns[0*124 +: 124] = 124'h41;
			columns[1*124 +: 124] = 124'h36;
			columns[2*124 +: 124] = 124'h28;
			columns[3*124 +: 124] = 124'h1464;
			columns[4*124 +: 124] = 124'h360;
			columns[5*124 +: 124] = 124'h15240;
			columns[6*124 +: 124] = 124'h1440;
			columns[7*124 +: 124] = 124'h40320;
		end
		1: begin // x^2
			columns[1*124 +: 124] = 1;
			columns[2*124 +: 124] = 2;
		end
		2: begin // x^3
			columns[1*124 +: 124] = 1;
			columns[3*124 +: 124] = 6;
		end
		3: begin // x(x+1)/2
			columns[1*124 +: 124] = 1;
			columns[2*124 +: 124] = 1;
		end
		4: begin // x^7
			columns[1*124 +: 124] = 1;
			columns[3*124 +: 124] = 124'h126;
			columns[5*124 +: 124] = 124'h1680;
			columns[7*124 +: 124] = 124'h5040;
		end
		5: begin // 100-x, using the 31-digit ten's complement of 1.
			columns[0*124 +: 124] = 124'h100;
			columns[1*124 +: 124] = {31{4'd9}};
		end
		6: begin // Full-width carry: 999...999 + 1.
			columns[0*124 +: 124] = {31{4'd9}};
			columns[1*124 +: 124] = 1;
		end
		default: ; // Empty machine.
	endcase
end
endmodule

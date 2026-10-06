// SPDX-License-Identifier: GPL-2.0-or-later
// MiSTer's decoded PS/2 events and configurable joystick buttons.
module de2_controls (
	input  wire         clk,
	input  wire         reset,
	input  wire         osd_open,
	input  wire [10:0]  ps2_key,
	input  wire [10:0]  joystick,
	input  wire         editable,
	input  wire [991:0] columns,
	output reg          toggle_run,
	output reg          step_cycle,
	output reg          step_phase,
	output reg          next_preset,
	output reg          reload,
	output reg          clear,
	output reg          help,
	output reg          edit,
	output reg  [2:0]   selected_column,
	output reg  [4:0]   selected_digit,
	output reg  [2:0]   edit_column,
	output reg  [4:0]   edit_digit,
	output reg  [3:0]   edit_value
);

reg last_toggle;
reg [511:0] held;
reg [10:0] last_joystick;
wire [10:0] pressed = joystick & ~last_joystick;
wire key_event = ps2_key[10] != last_toggle;
wire fresh_key = !held[ps2_key[8:0]];
wire [3:0] current_digit = columns[int'(selected_column)*124 + int'(selected_digit)*4 +: 4];

function automatic [4:0] number_key(input [8:0] keycode);
	begin
		case(keycode)
			9'h045,9'h070: number_key = 0;
			9'h016,9'h069: number_key = 1;
			9'h01e,9'h072: number_key = 2;
			9'h026,9'h07a: number_key = 3;
			9'h025,9'h06b: number_key = 4;
			9'h02e,9'h073: number_key = 5;
			9'h036,9'h074: number_key = 6;
			9'h03d,9'h06c: number_key = 7;
			9'h03e,9'h075: number_key = 8;
			9'h046,9'h07d: number_key = 9;
			default: number_key = 31;
		endcase
	end
endfunction

wire [4:0] number = number_key(ps2_key[8:0]);

always @(posedge clk) begin
	toggle_run <= 0;
	step_cycle <= 0;
	step_phase <= 0;
	next_preset <= 0;
	reload <= 0;
	clear <= 0;
	edit <= 0;
	last_toggle <= ps2_key[10];
	last_joystick <= joystick;
	if(reset) begin
		held <= 0;
		help <= 0;
		selected_column <= 0;
		selected_digit <= 0;
		edit_column <= 0;
		edit_digit <= 0;
		edit_value <= 0;
	end else begin
		if(key_event) held[ps2_key[8:0]] <= ps2_key[9];
		if(!osd_open) begin
			if(key_event && ps2_key[9]) begin
				if(fresh_key) begin
					case(ps2_key[8:0])
						9'h005: help <= !help;       // F1
						9'h076: help <= 0;           // Escape
						9'h029: if(!help) toggle_run <= 1;
						9'h006: if(!help) step_cycle <= 1; // F2
						9'h004: if(!help) step_phase <= 1; // F3
						9'h00c: if(!help) next_preset <= 1;// F4
						9'h003: if(!help) reload <= 1;     // F5
						9'h00b: if(!help) clear <= 1;      // F6
						default: ;
					endcase
				end
				if(!help) begin
					case(ps2_key[8:0])
						9'h16b: selected_column <= selected_column - 1'b1;
						9'h174: selected_column <= selected_column + 1'b1;
						9'h175: selected_digit <= (selected_digit == 30) ? 5'd0 : selected_digit + 1'b1;
						9'h172: selected_digit <= (selected_digit == 0) ? 5'd30 : selected_digit - 1'b1;
						9'h16c: selected_digit <= 30; // Home
						9'h169: selected_digit <= 0;  // End
						default: ;
					endcase
					if(editable) begin
						edit_column <= selected_column;
						edit_digit <= selected_digit;
						if(number < 10) begin
							edit <= 1;
							edit_value <= number[3:0];
							if(selected_digit != 0) selected_digit <= selected_digit - 1'b1;
						end else if(ps2_key[8:0] == 9'h05a || ps2_key[8:0] == 9'h15a || ps2_key[8:0] == 9'h079) begin
							edit <= 1;
							edit_value <= (current_digit == 9) ? 4'd0 : current_digit + 1'b1;
						end else if(ps2_key[8:0] == 9'h066 || ps2_key[8:0] == 9'h07b) begin
							edit <= 1;
							edit_value <= (current_digit == 0) ? 4'd9 : current_digit - 1'b1;
						end
					end
				end
			end
			if(!help) begin
				if(pressed[0]) selected_column <= selected_column + 1'b1;
				if(pressed[1]) selected_column <= selected_column - 1'b1;
				if(pressed[2]) selected_digit <= (selected_digit == 0) ? 5'd30 : selected_digit - 1'b1;
				if(pressed[3]) selected_digit <= (selected_digit == 30) ? 5'd0 : selected_digit + 1'b1;
				if(pressed[4]) step_cycle <= 1;
				if(pressed[5]) toggle_run <= 1;
				if(pressed[6]) step_phase <= 1;
				if(pressed[9]) next_preset <= 1;
				if(pressed[10]) reload <= 1;
				if(editable && (pressed[7] || pressed[8])) begin
					edit <= 1;
					edit_column <= selected_column;
					edit_digit <= selected_digit;
					edit_value <= pressed[7] ? ((current_digit == 9) ? 4'd0 : current_digit + 1'b1) :
						((current_digit == 0) ? 4'd9 : current_digit - 1'b1);
				end
			end
		end
	end
end

endmodule

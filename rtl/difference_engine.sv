// SPDX-License-Identifier: GPL-2.0-or-later
// Portable core; no vendor primitives or MiSTer framework dependencies.
module difference_engine #(
	parameter integer CLOCK_HZ = 50000000
) (
	input  wire         clk,
	input  wire         reset,
	input  wire         osd_open,
	input  wire [10:0]  ps2_key,
	input  wire [10:0]  joystick,
	input  wire [2:0]   menu_preset,
	input  wire [1:0]   speed,
	input  wire         menu_load,
	input  wire         menu_step,
	input  wire         menu_run,
	input  wire         downloading,
	input  wire         download_wr,
	input  wire [26:0]  download_addr,
	input  wire [7:0]   download_data,
	output wire         ce_pixel,
	output wire [7:0]   red,
	output wire [7:0]   green,
	output wire [7:0]   blue,
	output wire         hsync,
	output wire         vsync,
	output wire         de,
	output reg          running,
	output wire         busy,
	output wire [1:0]   phase,
	output wire [991:0] columns,
	output wire [23:0]  count,
	output wire         result_valid,
	output wire         load_error
);

wire [991:0] preset_columns;
wire [991:0] file_columns;
wire file_valid;
reg [991:0] saved_columns;
reg [2:0] preset;
reg custom;
reg initial_load;
reg [2:0] previous_menu;
reg old_load, old_step, old_run;

wire toggle_run, step_cycle, step_phase, next_preset, reload, clear;
wire help, edit;
wire [2:0] selected_column, edit_column;
wire [4:0] selected_digit, edit_digit;
wire [3:0] edit_value;
wire [247:0] warnings;
wire [7:0] carry_out;
reg cycle_pending;
reg phase_pending;
reg [26:0] timer;
reg [26:0] interval;

wire request_run = toggle_run || (menu_run && !old_run);
wire request_step = step_cycle || (menu_step && !old_step);
wire preset_changed = menu_preset != previous_menu;
wire request_preset = (menu_load && !old_load) || preset_changed || next_preset;
wire engine_load = initial_load || file_valid || request_preset || reload || clear;
wire [2:0] next_selection = next_preset ? preset + 1'b1 : menu_preset;
wire [991:0] load_columns = file_valid ? file_columns : clear ? 992'd0 :
	(reload && custom) ? saved_columns : preset_columns;
wire editable = !running && !cycle_pending && !phase_pending && !busy && phase == 0 && !downloading;
wire engine_edit = edit && editable && !engine_load;

// Pause while the OSD is open or a file is arriving. One in-flight 31-clock
// arithmetic phase may finish. Unsuccessful downloads preserve every column.
wire advance = !reset && !engine_load && !engine_edit && !busy && !osd_open && !help && !downloading &&
	(phase_pending || ((running || cycle_pending) && timer == 0));

de2_presets presets (.preset(request_preset ? next_selection : preset), .columns(preset_columns));
de2_loader loader (
	.clk(clk), .reset(reset), .downloading(downloading), .wr(download_wr),
	.address(download_addr), .data(download_data), .columns(file_columns),
	.valid(file_valid), .error(load_error)
);
de2_controls controls (
	.clk(clk), .reset(reset), .osd_open(osd_open || downloading),
	.ps2_key(ps2_key), .joystick(joystick), .editable(editable), .columns(columns),
	.toggle_run(toggle_run), .step_cycle(step_cycle), .step_phase(step_phase),
	.next_preset(next_preset), .reload(reload), .clear(clear), .help(help),
	.edit(edit), .selected_column(selected_column), .selected_digit(selected_digit),
	.edit_column(edit_column), .edit_digit(edit_digit), .edit_value(edit_value)
);
de2_engine engine (
	.clk(clk), .reset(reset), .load(engine_load), .load_columns(load_columns),
	.advance(advance), .edit(engine_edit), .edit_column(edit_column),
	.edit_digit(edit_digit), .edit_value(edit_value), .columns(columns),
	.warnings(warnings), .carry_out(carry_out), .phase(phase),
	.digit(), .busy(busy), .result_valid(result_valid), .count(count)
);

always @* begin
	case(speed)
		0: interval = 27'(CLOCK_HZ * 2);   // Eight seconds per result.
		1: interval = 27'(CLOCK_HZ / 4);   // One second per result.
		2: interval = 27'(CLOCK_HZ / 16);  // Four results per second.
		3: interval = 27'(CLOCK_HZ / 240); // Sixty results per second.
	endcase
end

always @(posedge clk) begin
	old_load <= menu_load;
	old_step <= menu_step;
	old_run <= menu_run;
	previous_menu <= menu_preset;
	if(reset) begin
		initial_load <= 1;
		preset <= menu_preset;
		custom <= 0;
		saved_columns <= 0;
		running <= 0;
		cycle_pending <= 0;
		phase_pending <= 0;
		timer <= 0;
	end else begin
		initial_load <= 0;
		if(engine_load) begin
			running <= 0;
			cycle_pending <= 0;
			phase_pending <= 0;
			timer <= 0;
			if(request_preset) begin
				preset <= next_selection;
				custom <= 0;
			end
			if(file_valid || clear) begin
				saved_columns <= load_columns;
				custom <= 1;
			end
		end else begin
			if(!osd_open && !help && !downloading && timer != 0) timer <= timer - 1'b1;
			if(advance) begin
				timer <= interval - 1'b1;
				phase_pending <= 0;
			end
			if(result_valid) cycle_pending <= 0;
			if(request_run) begin
				running <= !running;
				cycle_pending <= 0;
				phase_pending <= 0;
				timer <= 0;
			end else if(!running && request_step) begin
				cycle_pending <= 1;
				timer <= 0;
			end else if(!running && !cycle_pending && step_phase) phase_pending <= 1;
		end
	end
end

wire [3:0] paper_age;
wire [119:0] paper_value;
wire [15:0] paper_count;
wire paper_valid;
reg initial_print;
always @(posedge clk) begin
	if(reset) initial_print <= 0;
	else initial_print <= engine_load || engine_edit;
end
de2_printer printer (
	.clk(clk), .clear(reset || engine_load || engine_edit),
	.write(result_valid || initial_print), .value(columns[119:0]), .count(count[15:0]),
	.read_age(paper_age), .read_value(paper_value), .read_count(paper_count), .read_valid(paper_valid)
);

de2_video video (
	.clk(clk), .columns(columns), .warnings(warnings), .carry_out(carry_out),
	.phase(phase), .busy(busy), .running(running), .moving(running || cycle_pending || phase_pending),
	.selected_column(selected_column), .selected_digit(selected_digit), .editable(editable),
	.count(count), .preset(preset), .custom(custom), .speed(speed), .help(help),
	.load_error(load_error), .downloading(downloading),
	.paper_age(paper_age), .paper_value(paper_value), .paper_count(paper_count), .paper_valid(paper_valid),
	.ce_pixel(ce_pixel), .red(red), .green(green), .blue(blue),
	.hsync(hsync), .vsync(vsync), .de(de)
);

endmodule

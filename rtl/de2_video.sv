// SPDX-License-Identifier: GPL-2.0-or-later
// 640x480 at 25 MHz (800x525 total, 59.524 Hz), generated from CLK_50M.
// The raster runs through resets; MiSTer always receives stable sync.
module de2_video (
	input  wire         clk,
	input  wire [991:0] columns,
	input  wire [247:0] warnings,
	input  wire [7:0]   carry_out,
	input  wire [1:0]   phase,
	input  wire         busy,
	input  wire         running,
	input  wire         moving,
	input  wire [2:0]   selected_column,
	input  wire [4:0]   selected_digit,
	input  wire         editable,
	input  wire [23:0]  count,
	input  wire [2:0]   preset,
	input  wire         custom,
	input  wire [1:0]   speed,
	input  wire         help,
	input  wire         load_error,
	input  wire         downloading,
	output wire [3:0]   paper_age,
	input  wire [119:0] paper_value,
	input  wire [15:0]  paper_count,
	input  wire         paper_valid,
	output reg          ce_pixel = 0,
	output reg  [7:0]   red = 0,
	output reg  [7:0]   green = 0,
	output reg  [7:0]   blue = 0,
	output reg          hsync = 1,
	output reg          vsync = 1,
	output reg          de = 0
);

reg divider = 0;
reg [9:0] h = 0;
reg [9:0] v = 0;
wire visible = h < 640 && v < 480;
localparam [23:0] INK = 24'h14282b, BRASS = 24'hcfac68, LIGHT = 24'hecdbad;
localparam [23:0] MUTED = 24'h83968e, PAPER = 24'hecdec0, RED = 24'hdf7251, GREEN = 24'h8fd4a4;

reg [23:0] background;
reg [23:0] foreground;
reg [7:0] character;
reg [2:0] glyph_x, glyph_y;
reg [23:0] pixel_background = INK, pixel_foreground = LIGHT;
reg [7:0] pixel_character = " ";
reg [2:0] pixel_x = 0, pixel_y = 0;
reg pixel_visible = 0, pixel_hsync = 1, pixel_vsync = 1;
wire font_pixel;
de2_font font (.character(pixel_character), .x(pixel_x), .y(pixel_y), .pixel(font_pixel));

// Drawing tasks select a single glyph; there is only one shared font lookup.
task automatic text_at(
	input integer left, top, length,
	input [639:0] message,
	input [23:0] color,
	input integer scale
);
	reg [9:0] dx, dy;
	begin
		dx = h - 10'(left);
		dy = v - 10'(top);
		if(h >= 10'(left) && h < 10'(left+length*6*scale) &&
		   v >= 10'(top) && v < 10'(top+8*scale)) begin
			character = message[(10'(length-1)-dx/10'(6*scale))*10'd8 +: 8];
			glyph_x = 3'((dx/10'(scale))%10'd6);
			glyph_y = 3'(dy/10'(scale));
			foreground = color;
		end
	end
endtask

// Scan the regular grids with counters rather than dividing raster positions
// on the path into the large column/paper multiplexers.
reg [2:0] column_index = 0;
reg [5:0] wheel_x = 0;
reg [3:0] wheel_y = 0;
reg [4:0] wheel_index = 30;
reg [3:0] paper_row = 0;
reg [4:0] row_index = 0;
reg [5:0] char_index = 0;
reg [2:0] paper_x = 0;
reg [3:0] wheel_value;
reg [7:0] count_char;
wire [4:0] paper_digit = 5'(6'd34-char_index);
wire [2:0] count_digit = 3'd5 - 3'((h-10'd120)/10'd6);
wire [9:0] wheel_offset = {7'd0,column_index}*10'd124 + {3'd0,wheel_index,2'b00};
wire [7:0] warning_offset = {5'd0,column_index}*8'd31 + {3'd0,wheel_index};
assign paper_age = 4'd15 - paper_row;

always @* begin
	background = INK;
	foreground = LIGHT;
	character = " ";
	glyph_x = 0;
	glyph_y = 0;
	wheel_value = 0;
	count_char = " ";

	// Enamel case, engraved rules, and corner screws.
	if(h < 8 || h >= 632 || v < 8 || v >= 472) background = 24'h0b171b;
	if((v == 10 || v == 469) && h >= 10 && h < 630) background = 24'h6c674c;
	if((h == 10 || h == 629) && v >= 10 && v < 470) background = 24'h6c674c;
	if((h >= 15 && h <= 18 || h >= 621 && h <= 624) && (v >= 15 && v <= 18 || v >= 461 && v <= 464))
		background = BRASS;
	if(v == 56 && h >= 22 && h < 618) background = 24'h536356;
	text_at(24,28,17,"DIFFERENCE ENGINE",BRASS,2);
	if(custom) text_at(410,32,12,"CUSTOM TABLE",LIGHT,1);
	else case(preset)
		0: text_at(410,32,17,"MUSEUM POLYNOMIAL",LIGHT,1);
		1: text_at(410,32,7,"SQUARES",LIGHT,1);
		2: text_at(410,32,5,"CUBES",LIGHT,1);
		3: text_at(410,32,10,"TRIANGULAR",LIGHT,1);
		4: text_at(410,32,14,"SEVENTH POWERS",LIGHT,1);
		5: text_at(410,32,10,"DESCENDING",LIGHT,1);
		6: text_at(410,32,13,"CARRY CASCADE",LIGHT,1);
		7: text_at(410,32,5,"BLANK",LIGHT,1);
	endcase

	// Figure-wheel columns: most significant at the top; T is on the left.
	if(h >= 22 && h < 390 && v >= 64 && v < 410) begin
		background = 24'h102024;
		if(v == 80 || v == 81 || v == 400 || v == 401) background = BRASS;
		if(h == 24 || h == 25 || h == 386 || h == 387) background = 24'h877749;
	end
	if(h >= 34 && h < 386) begin
		if(v >= 68 && v < 76 && wheel_x >= 8 && wheel_x < 20) begin
			character = (wheel_x < 14) ? ((column_index == 0) ? "T" : "D") :
				((column_index == 0) ? 8'd32 : 8'd48 + 8'(column_index));
			glyph_x = 3'((wheel_x-6'd8)%6'd6);
			glyph_y = 3'(v-10'd68);
			foreground = (column_index == selected_column) ? LIGHT : MUTED;
		end
		if(v >= 77 && v < 79 && wheel_x >= 10 && wheel_x < 18)
			background = (moving || busy) && (column_index[0] == phase[1]) ? GREEN : 24'h3e4b40;
		if(v >= 86 && v < 396) begin
			wheel_value = columns[wheel_offset +: 4];
			if(wheel_x < 30 && wheel_y < 9) begin
				background = (wheel_x < 4 || wheel_x >= 26) ? 24'h7b603b :
					(wheel_y == 0) ? 24'he1c18a : (wheel_y == 8) ? 24'h6e5435 : 24'hb99962;
				if(column_index == selected_column && wheel_index == selected_digit) begin
					background = editable ? LIGHT : 24'h96b4aa;
					if(wheel_x == 0 || wheel_x == 29 || wheel_y == 0 || wheel_y == 8) background = RED;
				end
				if(wheel_x >= 12 && wheel_x < 18 && wheel_y >= 1 && wheel_y < 8) begin
					character = 8'd48 + {4'd0,wheel_value};
					glyph_x = 3'(wheel_x-12);
					glyph_y = 3'(wheel_y-1);
					foreground = (wheel_value == 0) ? 24'h706046 : INK;
				end
			end
			if(wheel_x >= 32 && wheel_x < 35 && wheel_y >= 3 && wheel_y < 6)
				background = warnings[warning_offset] ? RED : 24'h253d3d;
		end
		if(v >= 403 && v < 407 && wheel_x >= 12 && wheel_x < 17)
			background = carry_out[column_index] ? RED : 24'h3e4b40;
	end

	// Paper roll. Newest completed result appears at the bottom.
	if(h >= 404 && h < 626 && v >= 63 && v < 410) begin
		background = PAPER;
		if(h < 408 || h >= 622) background = 24'hbcac90;
		if(v == 92) background = 24'hbda980;
		if(v >= 110 && v < 382 && h >= 412 && h < 622) begin
			if(row_index < 8 && paper_valid) begin
				if(char_index < 4) character = 8'd48 + {4'd0,paper_count[{(2'd3-char_index[1:0]),2'b00} +: 4]};
				else if(char_index == 4) character = " ";
				else begin
					character = 8'd48 + {4'd0,paper_value[{paper_digit,2'b00} +: 4]};
					if(char_index < 34 && (paper_value >> {paper_digit,2'b00}) == 0) character = " ";
				end
				glyph_x = paper_x;
				glyph_y = 3'(row_index);
				foreground = (paper_age == 0) ? INK : 24'h645d4d;
			end
			if(row_index == 13) background = 24'hdfd0b1;
		end
	end
	text_at(412,76,4,"STEP",INK,1);
	text_at(448,76,6,"RESULT",INK,1);

	// Operator status strip.
	text_at(24,416,6,running ? "RUN   " : moving ? "CRANK " : "PAUSED",running ? GREEN : LIGHT,1);
	text_at(84,416,6,"CYCLE ",MUTED,1);
	if(h >= 120 && h < 156 && v >= 416 && v < 424) begin
		count_char = 8'd48 + {4'd0,count[{count_digit,2'b00} +: 4]};
		character = count_char;
		glyph_x = 3'((h-10'd120)%10'd6);
		glyph_y = 3'(v-10'd416);
		foreground = LIGHT;
	end
	case(phase)
		0: text_at(178,416,9,"1/4 ADD  ",MUTED,1);
		1: text_at(178,416,9,"2/4 CARRY",RED,1);
		2: text_at(178,416,9,"3/4 ADD  ",MUTED,1);
		3: text_at(178,416,9,"4/4 CARRY",RED,1);
	endcase
	case(speed)
		0: text_at(578,418,6,"8 SEC ",MUTED,1);
		1: text_at(578,418,6,"1 SEC ",MUTED,1);
		2: text_at(578,418,6,"4 /SEC",MUTED,1);
		3: text_at(578,418,6,"60/SEC",MUTED,1);
	endcase
	if(v == 433 && h >= 22 && h < 618) background = 24'h536356;
	if(downloading) text_at(24,450,13,"LOADING TABLE",BRASS,1);
	else if(load_error) text_at(24,450,53,"COULD NOT LOAD TABLE. CHOOSE A .DE2 FILE IN THE MENU.",RED,1);
	else text_at(24,450,53,"SPACE RUN/PAUSE     F2 CRANK     F1 HELP     F12 MENU",MUTED,1);

	// A separate operator card avoids crowding the mechanical panel.
	if(help && h >= 56 && h < 584 && v >= 72 && v < 412) begin
		background = PAPER;
		character = " ";
		if(h == 58 || h == 581 || v == 74 || v == 409) background = BRASS;
		text_at(80,94,8,"CONTROLS",INK,2);
		text_at(80,136,18,"SPACE  RUN / PAUSE",INK,1);
		text_at(80,154,53,"F2     CRANK ONCE              F3   ADVANCE ONE PHASE",INK,1);
		text_at(80,172,50,"F4     NEXT TABLE   F5   RELOAD TABLE   F6   CLEAR",INK,1);
		text_at(80,206,55,"ARROWS      SELECT A WHEEL     HOME / END   TOP / UNITS",INK,1);
		text_at(80,224,56,"0-9         SET DIGIT          ENTER / BACKSPACE   + / -",INK,1);
		text_at(80,250,36,"Pause at the end of a cycle to edit.",INK,1);
		text_at(80,266,37,"F2 finishes a partially turned cycle.",INK,1);
		text_at(80,300,30,"Red pins show pending carries.",INK,1);
		text_at(80,316,49,"A lamp below a column means a carry past the top.",INK,1);
		text_at(80,350,40,"F12   TABLES, SPEED AND CONTROLLER SETUP",INK,1);
		text_at(80,386,18,"F1 OR ESC TO CLOSE",24'h85633c,1);
	end
end

// Register the selected glyph before font lookup and color composition.
// Blanking and sync traverse the same two stages as the rendered pixel.
always @(posedge clk) begin
	divider <= !divider;
	ce_pixel <= divider;
	if(divider) begin
		if(h == 33) begin
			column_index <= 0;
			wheel_x <= 0;
		end else if(h >= 34 && h < 385) begin
			if(wheel_x == 43) begin
				wheel_x <= 0;
				column_index <= column_index + 1'b1;
			end else wheel_x <= wheel_x + 1'b1;
		end
		if(h == 411) begin
			char_index <= 0;
			paper_x <= 0;
		end else if(h >= 412 && h < 621) begin
			if(paper_x == 5) begin
				paper_x <= 0;
				char_index <= char_index + 1'b1;
			end else paper_x <= paper_x + 1'b1;
		end
		if(h == 799) begin
			h <= 0;
			v <= (v == 524) ? 10'd0 : v + 1'b1;
			if(v == 85) begin
				wheel_y <= 0;
				wheel_index <= 30;
			end else if(v >= 86 && v < 395) begin
				if(wheel_y == 9) begin
					wheel_y <= 0;
					wheel_index <= wheel_index - 1'b1;
				end else wheel_y <= wheel_y + 1'b1;
			end
			if(v == 109) begin
				paper_row <= 0;
				row_index <= 0;
			end else if(v >= 110 && v < 381) begin
				if(row_index == 16) begin
					row_index <= 0;
					paper_row <= paper_row + 1'b1;
				end else row_index <= row_index + 1'b1;
			end
		end else h <= h + 1'b1;
		pixel_hsync <= !(h >= 656 && h < 752);
		pixel_vsync <= !(v >= 490 && v < 492);
		pixel_visible <= visible;
		pixel_character <= character;
		pixel_x <= glyph_x;
		pixel_y <= glyph_y;
		pixel_foreground <= foreground;
		pixel_background <= background;
		hsync <= pixel_hsync;
		vsync <= pixel_vsync;
		de <= pixel_visible;
		{red,green,blue} <= pixel_visible ? (font_pixel ? pixel_foreground : pixel_background) : 24'd0;
	end
end

endmodule

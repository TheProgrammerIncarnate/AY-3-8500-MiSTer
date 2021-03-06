//============================================================================
//  AY-3-8500 for MiSTer
//
//  Copyright (C) 2019 Cole Johnson
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [44:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        VGA_CLK,

	//Multiple resolutions are supported using different VGA_CE rates.
	//Must be based on CLK_VIDEO
	output        VGA_CE,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)

	//Base video clock. Usually equals to CLK_SYS.
	output        HDMI_CLK,

	//Multiple resolutions are supported using different HDMI_CE rates.
	//Must be based on CLK_VIDEO
	output        HDMI_CE,

	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,   // = ~(VBlank | HBlank)
	output  [1:0] HDMI_SL,   // scanlines fx

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] HDMI_ARX,
	output  [7:0] HDMI_ARY,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S    // 1 - signed audio samples, 0 - unsigned
);

assign LED_USER  = 0;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign HDMI_ARX = status[1] ? 8'd16 : 8'd4;
assign HDMI_ARY = status[1] ? 8'd9  : 8'd3;

`include "build_id.v" 
localparam CONF_STR = {
	"AY-3-8500;;",
	"-;",
	"O1,Aspect Ratio,Original,Wide;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"O6,Invisiball,OFF,ON;",
	"O7A,Color Pallette,Mono,Greyscale,RGB1,RGB2,Field,Ice,Christmas,Marksman,Las Vegas;",
	"-;",
	"R0,Reset;",
	"V,v2",`BUILD_DATE
};
////////////////////   CLOCKS   ///////////////////

wire clk_sys, clk_vid, clk_off;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys), // 7.159mhz
	.outclk_1(clk_vid), // 28.636mhz
	.locked(pll_locked)
);

///////////////////////IN+OUT///////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire [10:0] ps2_key;

wire [15:0] joystick_0, joystick_1;
wire [15:0] joy = joystick_0;
wire [15:0] joy2 = joystick_1;
wire [15:0] joystick_analog_0;
wire [15:0] joystick_analog_1;
reg initReset_n = 0;
always @(posedge clk_sys) begin
	reg old_download = 0;
	old_download <= ioctl_download;
	
	if(old_download & ~ioctl_download) initReset_n <= 1;
end

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.forced_scandoubler(forced_scandoubler),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_analog_0(joystick_analog_0),
	.joystick_analog_1(joystick_analog_1),	
	.ps2_key(ps2_key)
);

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code)
			'h01D: btnP1Up <= pressed; //W
			'h01B: btnP1Down <= pressed; //S
			'hX75: btnP2Up <= pressed; // up
			'hX72: btnP2Down <= pressed; // down
			'h029: btnServe <= pressed; // space
			'h016: gameBtns[0:0] <= pressed; // 1
			'h01E: gameBtns[1:1] <= pressed; // 2
			'h026: gameBtns[2:2] <= pressed; // 3
			'h025: gameBtns[3:3] <= pressed; // 4
			'h02E: gameBtns[4:4] <= pressed; // 5
			'h036: gameBtns[5:5] <= pressed; // 6
			'h03D: gameBtns[6:6] <= pressed; // 7
			'h01A: btnAngle <= pressed; // Z
			'h022: btnSpeed <= pressed; // X
			'h021: btnSize <= pressed; // C
			'h02A: btnAutoserve <= pressed; // V
			'h03A: btnMiss <= pressed; //M
			'h033: btnHit <= pressed; //H
			'h02D: btnReset <= pressed; //R
		endcase
	end
end

reg btnP1Up = 0;
reg btnP1Down = 0;
reg btnP2Up = 0;
reg btnP2Down = 0;
reg btnServe = 0;
reg btnReset = 0;
reg [7:0] gameBtns = 0;
reg [7:0] gameSelect = 7'b0000001;//Default to Tennis
reg btnAngle, btnAngleOld = 0;
reg btnSpeed, btnSpeedOld = 0;
reg btnSize, btnSizeOld = 0;
reg btnAutoserve, btnAutoserveOld = 0;
reg btnMiss = 0;
reg btnHit = 0;

reg [10:0] toggleInputs = 0;
reg angle = 0;
reg speed = 0;
reg size = 0;
reg autoserve = 0;
//Handle button toggling
always @(posedge clk_sys) begin
	btnAngleOld <= btnAngle;
	btnSpeedOld <= btnSpeed;
	btnSizeOld <= btnSize;
	btnAutoserveOld <= btnAutoserve;
	if(gameBtns[0:0])
		gameSelect = 7'b0000001;//Tennis
	else if(gameBtns[1:1])
		gameSelect = 7'b0000010;//Soccer
	else if(gameBtns[2:2])
		gameSelect = 7'b0000100;//Handicap (using a dummy bit)
	else if(gameBtns[3:3])
		gameSelect = 7'b0001000;//Squash
	else if(gameBtns[4:4])
		gameSelect = 7'b0010000;//Practice
	else if(gameBtns[5:5])
		gameSelect = 7'b0100000;//Rifle 1
	else if(gameBtns[6:6])
		gameSelect = 7'b1000000;//Rifle 2
	if(btnAngle & !btnAngleOld)
		angle <= !angle;
	if(btnSpeed & !btnSpeedOld)
		speed <= !speed;
	if(btnSize & !btnSizeOld)
		size <= !size;
	if(btnAutoserve & !btnAutoserveOld)
		autoserve <= !autoserve;
end
/////////////////Paddle Emulation//////////////////
wire [4:0] paddleMoveSpeed = speed ? 8 : 5;//Faster paddle movement when ball speed is high
reg [8:0] player1pos = 8'd128;
reg [8:0] player2pos = 8'd128;
reg [8:0] player1cap = 0;
reg [8:0] player2cap = 0;
reg hsOld = 0;
reg vsOld = 0;
always @(posedge clk_sys) begin
	hsOld <= hs;
	vsOld <= vs;
	if(vs & !vsOld) begin
		player1cap <= player1pos;
		player2cap <= player2pos;
		if(btnP1Up & player1pos>0)
			player1pos <= player1pos - paddleMoveSpeed;
		else if(btnP1Down & player1pos<8'hFF)
			player1pos <= player1pos + paddleMoveSpeed;
		if(btnP2Up & player2pos>0)
			player2pos <= player2pos - paddleMoveSpeed;
		else if(btnP2Down & player2pos < 8'hFF)
			player2pos <= player2pos + paddleMoveSpeed;
	end
	else if(hs & !hsOld) begin
		if(player1cap!=0)
			player1cap <= player1cap - 1;
		if(player2cap!=0)
			player2cap <= player2cap - 1;
	end
end
//Signal outputs (active-high except for sync)
wire audio;
wire rpOut;
wire lpOut;
wire ballOut;
wire scorefieldOut;
wire syncH;
wire syncV;
wire isBlanking;

//Misc pins
wire hitIn = (gameBtns[5:5] | gameBtns[6:6]) ? btnHit : audio;
//Still unknown why example schematic instructs connecting hitIn pin to audio during ball games
wire shotIn = (gameBtns[5:5] | gameBtns[6:6]) ? (btnHit | btnMiss) : 1;
wire lpIN = (player1cap == 0);
wire rpIN = (player2cap == 0);
wire lpIN_reset;//We don't use these signals, instead the VSYNC signal (identical) is directly accessed
wire rpIN_reset;
wire chipReset = btnReset | status[0];
ay38500NTSC the_chip
(
	.clk(clk_sys),
	.superclock(CLK_50M),
	.reset(!chipReset),
	.pinRPout(rpOut),
	.pinLPout(lpOut),
	.pinBallOut(ballOut),
	.pinSFout(scorefieldOut),
	.syncH(syncH),
	.syncV(syncV),
	.pinSound(audio),
	.pinManualServe(!(autoserve | btnServe)),
	.pinBallAngle(!angle),
	.pinBatSize(!size),
	.pinBallSpeed(!speed),
	.pinPractice(!gameSelect[4:4]),
	.pinSquash(!gameSelect[3:3]),
	.pinSoccer(!gameSelect[1:1]),
	.pinTennis(!gameSelect[0:0]),
	.pinRifle1(!gameSelect[5:5]),
	.pinRifle2(!gameSelect[6:6]),
	.pinHitIn(hitIn),
	.pinShotIn(shotIn),
	.pinLPin(lpIN),
	.pinRPin(rpIN)
);

/////////////////////VIDEO//////////////////////
wire hs = !syncH;
wire vs = !syncV;
wire hblank = !hs;
wire vblank = !vs;
wire [3:0] r,g,b;
wire showBall = !status[6:6] | (ballHide>0);
reg [5:0] ballHide = 0;
reg audioOld = 0;
always @(posedge clk_sys) begin
	audioOld <= audio;
	if(!audioOld & audio)
		ballHide <= 5'h1F;
	else if(vs & !vsOld & ballHide!=0)
		ballHide <= ballHide - 1;
end
reg [12:0] colorOut = 0;
always @(posedge clk_sys) begin
	if(ballOut & showBall) begin
		case(status[11:7])
			'h0: colorOut <= 12'hFFF;//Mono
			'h1: colorOut <= 12'hFFF;//Greyscale
			'h2: colorOut <= 12'hF00;//RGB1
			'h3: colorOut <= 12'hFFF;//RGB2
			'h4: colorOut <= 12'h000;//Field
			'h5: colorOut <= 12'h000;//Ice
			'h6: colorOut <= 12'hFFF;//Christmas
			'h7: colorOut <= 12'hFFF;//Marksman
			'h8: colorOut <= 12'hFF0;//Las Vegas
		endcase
	end
	else if(lpOut) begin
		case(status[11:7])
			'h0: colorOut <= 12'hFFF;//Mono
			'h1: colorOut <= 12'hFFF;//Greyscale
			'h2: colorOut <= 12'h0F0;//RGB1
			'h3: colorOut <= 12'h00F;//RGB2
			'h4: colorOut <= 12'hF00;//Field
			'h5: colorOut <= 12'hF00;//Ice
			'h6: colorOut <= 12'hF00;//Christmas
			'h7: colorOut <= 12'hFF0;//Marksman
			'h8: colorOut <= 12'hFF0;//Las Vegas
		endcase
	end
	else if(rpOut) begin
		case(status[11:7])
			'h0: colorOut <= 12'hFFF;//Mono
			'h1: colorOut <= 12'h000;//Greyscale
			'h2: colorOut <= 12'h0F0;//RGB1
			'h3: colorOut <= 12'hF00;//RGB2
			'h4: colorOut <= 12'h00F;//Field
			'h5: colorOut <= 12'h030;//Ice
			'h6: colorOut <= 12'h030;//Christmas
			'h7: colorOut <= 12'h000;//Marksman
			'h8: colorOut <= 12'hF0F;//Las Vegas
		endcase
	end
	else if(scorefieldOut) begin
		case(status[11:7])
			'h0: colorOut <= 12'hFFF;//Mono
			'h1: colorOut <= 12'hFFF;//Greyscale
			'h2: colorOut <= 12'h00F;//RGB1
			'h3: colorOut <= 12'h0F0;//RGB2
			'h4: colorOut <= 12'hFFF;//Field
			'h5: colorOut <= 12'h55F;//Ice
			'h6: colorOut <= 12'hFFF;//Christmas
			'h7: colorOut <= 12'hFFF;//Marksman
			'h8: colorOut <= 12'hF90;//Las Vegas
		endcase
	end
	else begin
		case(status[11:7])
			'h0: colorOut <= 12'h000;//Mono
			'h1: colorOut <= 12'h999;//Greyscale
			'h2: colorOut <= 12'h000;//RGB1
			'h3: colorOut <= 12'h000;//RGB2
			'h4: colorOut <= 12'h4F4;//Field
			'h5: colorOut <= 12'hCCF;//Ice
			'h6: colorOut <= 12'h000;//Christmas
			'h7: colorOut <= 12'h0D0;//Marksman
			'h8: colorOut <= 12'h000;//Las Vegas
		endcase
	end
end
arcade_fx #(375, 12) arcade_video
(
        .*,

        .clk_video(clk_vid),
        .ce_pix(clk_sys),

        .RGB_in(colorOut),
        .HBlank(hblank),
        .VBlank(vblank),
        .HSync(hs),
        .VSync(vs),

        .fx(status[5:3])
        //.no_rotate(status[2])
);
////////////////////AUDIO////////////////////////
assign AUDIO_L = {audio, 15'b0};
assign AUDIO_R = AUDIO_L;
assign AUDIO_S = 0;

endmodule

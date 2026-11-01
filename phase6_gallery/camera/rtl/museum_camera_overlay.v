// Normal viewing only adds a compact status chip. RGB332 preview exists only
// in maintenance; no full-screen calibration fill, mask RAM or second font ROM.
module museum_camera_overlay #(parameter STALE_CYCLES=12500000,parameter EXTERNAL_ENABLE=0)(
 input clk,rst,de,input [9:0] x,y,input [23:0] base_rgb,
 input maintenance,preview_visible,background_ready,fault,recognition_enabled,input [2:0] stage,input armed,
 input preview_de,preview_clear,input [9:0] preview_x,preview_y,input [23:0] preview_rgb,
 input nav_ready,output reg [23:0] rgb);
 wire write_pixel=preview_de && preview_x<640 && preview_y<480 && preview_x[2:0]==0 && preview_y[2:0]==0 && !rst && !preview_clear;
 wire [12:0] wa=(preview_y>>3)*80+(preview_x>>3);
 wire [7:0] wd={preview_rgb[23:21],preview_rgb[15:13],preview_rgb[7:6]};
 wire [9:0] nx=x==799 ? 0 : x+1'b1;
 wire [9:0] ny=x==799 ? (y==524 ? 0 : y+1'b1) : y;
 wire next_in=nx>=456 && nx<616 && ny>=288 && ny<408;
 wire [6:0] col=(nx-456)>>1;
 wire [12:0] ra=next_in ? ((ny-288)>>1)*80+79-col : 0;
 (* ram_style="bram_32k" *) reg [7:0] head[0:4095];
 (* ram_style="bram_9k" *) reg [7:0] tail[0:703];
 reg [7:0] hq,tq,forward;reg tail_q,hforward,tforward;
 reg have_frame;localparam AW=$clog2(STALE_CYCLES+1);reg [AW-1:0] age;
 always @(posedge clk)begin
  hq<=head[ra[11:0]];tq<=tail[ra[9:0]];tail_q<=ra[12];forward<=wd;
  hforward<=write_pixel && !wa[12] && wa[11:0]==ra[11:0];
  tforward<=write_pixel && wa[12] && wa[9:0]==ra[9:0];
  if(write_pixel && !wa[12])head[wa[11:0]]<=wd;
  if(write_pixel && wa[12])tail[wa[9:0]]<=wd;
  if(rst || preview_clear)begin have_frame<=0;age<=0;end
  else begin
   if(preview_de)age<=0;else if(age<STALE_CYCLES)age<=age+1'b1;
   if(age>=STALE_CYCLES-1 && !preview_de)have_frame<=0;
   else if(preview_de && preview_x==639 && preview_y==479)have_frame<=1;
  end
 end
 wire [7:0] q=tail_q ? (tforward ? forward : tq) : (hforward ? forward : hq);
 wire [23:0] preview={{q[7:5],q[7:5],q[7:6]},{q[4:2],q[4:2],q[4:3]},{q[1:0],q[1:0],q[1:0],q[1:0]}};
 // Glyph function is the same 3x5 Latin alphabet as the archived overlay.
 function [14:0] glyph(input [7:0] ch);begin case(ch)
  8'd65:glyph=15'b010101111101101;
  8'd66:glyph=15'b110101110101110;
  8'd67:glyph=15'b011100100100011;
  8'd68:glyph=15'b110101101101110;
  8'd69:glyph=15'b111100110100111;
  8'd70:glyph=15'b111100110100100;
  8'd71:glyph=15'b011100101101011;
  8'd72:glyph=15'b101101111101101;
  8'd73:glyph=15'b111010010010111;
  8'd74:glyph=15'b001001001101010;
  8'd75:glyph=15'b101101110101101;
  8'd76:glyph=15'b100100100100111;
  8'd77:glyph=15'b101111111101101;
  8'd78:glyph=15'b101111111111101;
  8'd79:glyph=15'b010101101101010;
  8'd80:glyph=15'b110101110100100;
  8'd81:glyph=15'b010101101111011;
  8'd82:glyph=15'b110101110101101;
  8'd83:glyph=15'b011100010001110;
  8'd84:glyph=15'b111010010010010;
  8'd85:glyph=15'b101101101101111;
  8'd86:glyph=15'b101101101101010;
  8'd87:glyph=15'b101101111111101;
  8'd88:glyph=15'b101101010101101;
  8'd89:glyph=15'b101101010010010;
  8'd90:glyph=15'b111001010100111;
  8'd48:glyph=15'b111101101101111;
  8'd49:glyph=15'b010110010010111;
  8'd50:glyph=15'b110001010100111;
  8'd51:glyph=15'b110001010001110;
  8'd52:glyph=15'b101101111001001;
  8'd53:glyph=15'b111100110001110;
  8'd54:glyph=15'b011100111101111;
  8'd55:glyph=15'b111001010010010;
  8'd56:glyph=15'b111101111101111;
  8'd57:glyph=15'b111101111001110;
  8'd45:glyph=15'b000000111000000;
  default:glyph=0;
 endcase end endfunction

 reg [95:0] status;
 reg [7:0] ch;reg [14:0] bits;
 reg [4:0] column;reg [1:0] gx;reg [2:0] gy;
 // 3x5 glyphs need four address bits, not signed 32-bit multiplies/DSPs.
 wire [3:0] glyph_row_offset={1'b0,gy}+{gy,1'b0};
 wire [3:0] glyph_bit=4'd14-glyph_row_offset-{2'b00,gx};
 always @*begin
  status=fault ? "CAM ERROR   " : maintenance ? "CAM SETUP   " : EXTERNAL_ENABLE && !recognition_enabled ? "CAM OFF     " :
         !background_ready ? "CAM WAIT    " : !nav_ready ? "CAM LOADING " :
         armed ? "CAM ARMED   " : "CAM READY   ";
  rgb=base_rgb;ch=32;bits=0;column=0;gx=0;gy=0;
  if(x>=488 && x<616 && y>=60 && y<76)begin
   rgb=fault ? 24'hf3d9d0 : 24'he4eadc;
   if(y>=63 && y<73)begin
    column=(x-488)>>3;gx=((x-488)&7)>>1;gy=(y-63)>>1;
    if(column<12)ch=status[(11-column)*8+:8];
    if(column==12)ch="S";if(column==13)ch=48+stage;
    if(column==14)ch="A";if(column==15)ch=armed ? "1" : "0";
    bits=glyph(ch);if(gx<3 && bits[glyph_bit])rgb=24'h343d38;
   end
  end
  if(maintenance && preview_visible && x>=456 && x<616 && y>=288 && y<408)begin
   rgb=have_frame ? preview : 24'he4eadc;
   if(x==456 || x==615 || y==288 || y==407)rgb=24'h405b43;
  end
  if(!de || rst)rgb=0;
 end
endmodule

// Calibration skin view, Gallery RGB332 inset and status; no wrist detector.
module camera_pose_overlay #(parameter integer PREVIEW_STALE_CYCLES=12500000,parameter SWIPE_MODE=0,parameter MIRROR_X=0,parameter INTEGRATED_STYLE=0,parameter integer ROI_Y0=48,ROI_Y1=432)(
 input wire clk,rst,de,input wire [9:0] x,y,
 input wire [23:0] base_rgb,input wire calibration,background_ready,fault,
 input wire [2:0] stage,error,pose,input wire collecting,armed,input wire [31:0] event_sequence,
 input wire mask_valid,input wire [6:0] mask_x,input wire [5:0] mask_y,input wire skin,
 input wire preview_de,preview_clear,input wire [9:0] preview_x,preview_y,
 input wire [23:0] preview_rgb,
 input wire nav_ready, input wire target_visible,input wire [9:0] target_x,target_y,
 input wire preview_enable,diagnostics,recognition_enabled,
 input wire preparing,source_fault,nav_overflow,
 output reg [23:0] rgb);
 (* ram_style="bram_9k" *) reg mask[0:4799];reg mask_q;
 wire [9:0] nx=x==799 ? 0 : x+1'b1;
 wire [9:0] ny=x==799 ? (y==524 ? 0 : y+1'b1) : y;
 reg roi_corner_hit;
 always @(posedge clk)roi_corner_hit<=
       (((ny==50 || ny==79) && ((nx>=550 && nx<=555) || (nx>=578 && nx<=583))) ||
        ((nx==550 || nx==583) && ((ny>=50 && ny<=55) || (ny>=74 && ny<=79))));
 wire small_next=nx>=504 && nx<632 && ny>=8 && ny<120;
 wire [6:0] small_col=8+((nx-504)>>1);
 wire [5:0] small_row=2+((ny-8)>>1);
 wire in_next=INTEGRATED_STYLE ? small_next : nx>=160 && nx<480 && ny>=160 && ny<400;
 wire [6:0] mask_col=INTEGRATED_STYLE ? small_col : (nx-160)>>2;
 wire [12:0] address=in_next ? (INTEGRATED_STYLE ? small_row : ((ny-160)>>2))*80+(MIRROR_X ? 79-mask_col : mask_col) : 0;
 // Reuse the source stream's 80x60 sampling. Its (639,479) marker is emitted
 // only after a complete, good frame. No preview traffic feeds the classifier.
 wire preview_write=preview_de && preview_x<640 && preview_y<480 &&
                    preview_x[2:0]==0 && preview_y[2:0]==0 && !preview_clear && !rst;
 wire [12:0] preview_wr=(preview_y>>3)*80+(preview_x>>3);
 wire [7:0] preview_data={preview_rgb[23:21],preview_rgb[15:13],preview_rgb[7:6]};
 wire inset_next=INTEGRATED_STYLE ? small_next : nx>=464 && nx<624 && ny>=344 && ny<464;
 wire [6:0] preview_col=INTEGRATED_STYLE ? small_col : (nx-464)>>1;
 wire [12:0] preview_rd=inset_next ? (INTEGRATED_STYLE ? small_row : ((ny-344)>>1))*80+(MIRROR_X ? 79-preview_col : preview_col) : 0;
 // Reflect the rendered cursor about the same window axis as the sampled image.
 // Source coordinates and telemetry remain unchanged.
 wire [9:0] cursor_x=calibration ? (MIRROR_X ? 477-(target_x>>1) : 162+(target_x>>1)) :
                                                (MIRROR_X ? 622-(target_x>>2) : 465+(target_x>>2));
 wire [9:0] cursor_y=calibration ? 160+(target_y>>1) : 344+(target_y>>2);
 (* ram_style="bram_32k" *) reg [7:0] preview_head[0:4095];
 (* ram_style="bram_9k" *) reg [7:0] preview_tail[0:703];
 reg [7:0] head_q,tail_q,forward_q;
 reg head_forward,tail_forward,tail_select,preview_ready;
 localparam PAW=PREVIEW_STALE_CYCLES>1 ? $clog2(PREVIEW_STALE_CYCLES+1) : 1;
 reg [PAW-1:0] preview_age;
 // Plain synchronous read/write ports preserve block RAM inference. Collision
 // forwarding is outside the RAM read registers, with the same cycle latency.
 always @(posedge clk)begin
  head_q<=preview_head[preview_rd[11:0]];
  tail_q<=preview_tail[preview_rd[9:0]];
  tail_select<=preview_rd[12];
  forward_q<=preview_data;
  head_forward<=preview_write && !preview_wr[12] && preview_rd[11:0]==preview_wr[11:0];
  tail_forward<=preview_write && preview_wr[12] && preview_rd[9:0]==preview_wr[9:0];
  if(rst || preview_clear)begin preview_ready<=0;preview_age<=0;end
  else begin
   if(preview_de)preview_age<=0;
   else if(preview_age<PREVIEW_STALE_CYCLES)preview_age<=preview_age+1'b1;
   if(preview_age>=PREVIEW_STALE_CYCLES-1 && !preview_de)preview_ready<=0;
   else if(preview_de && preview_x==639 && preview_y==479)preview_ready<=1;
  end
 end
 always @(posedge clk)begin
  if(preview_write && !preview_wr[12])preview_head[preview_wr[11:0]]<=preview_data;
  if(preview_write && preview_wr[12])preview_tail[preview_wr[9:0]]<=preview_data;
 end
 wire [7:0] preview_q=tail_select ? (tail_forward ? forward_q : tail_q) :
                                                (head_forward ? forward_q : head_q);
 wire [23:0] preview_color={{preview_q[7:5],preview_q[7:5],preview_q[7:6]},
                            {preview_q[4:2],preview_q[4:2],preview_q[4:3]},
                            {preview_q[1:0],preview_q[1:0],preview_q[1:0],preview_q[1:0]}};
 // Read ahead one scan pixel: RAM data aligns with the next scan coordinate.
 always @(posedge clk)begin
  mask_q<=mask[address];
  if(mask_valid && mask_x<80 && mask_y<60)mask[mask_y*80+mask_x]<=skin;
 end
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
function [15:0] panel_char(input [3:0] message,input [5:0] pos);begin case({message,pos})
10'd0:panel_char=16'h76f8;
10'd1:panel_char=16'h673a;
10'd2:panel_char=16'h9884;
10'd3:panel_char=16'h89c8;
10'd64:panel_char=16'h56fe;
10'd65:panel_char=16'h50cf;
10'd66:panel_char=16'h6d41;
10'd67:panel_char=16'h5f02;
10'd68:panel_char=16'h5e38;
10'd128:panel_char=16'h8bf7;
10'd129:panel_char=16'h5148;
10'd130:panel_char=16'h79fb;
10'd131:panel_char=16'h5f00;
10'd132:panel_char=16'h624b;
10'd192:panel_char=16'h6b63;
10'd193:panel_char=16'h5728;
10'd194:panel_char=16'h51c6;
10'd195:panel_char=16'h5907;
10'd256:panel_char=16'h8bf7;
10'd257:panel_char=16'h5c06;
10'd258:panel_char=16'h624b;
10'd259:panel_char=16'h5c45;
10'd260:panel_char=16'h4e2d;
10'd320:panel_char=16'h53ef;
10'd321:panel_char=16'h4ee5;
10'd322:panel_char=16'h6ed1;
10'd323:panel_char=16'h52a8;
10'd324:panel_char=16'h4e86;
10'd384:panel_char=16'h6b63;
10'd385:panel_char=16'h5728;
10'd386:panel_char=16'h8bc6;
10'd387:panel_char=16'h522b;
10'd448:panel_char=16'h8bf7;
10'd449:panel_char=16'h56de;
10'd450:panel_char=16'h4e2d;
10'd451:panel_char=16'h505c;
10'd452:panel_char=16'h7a33;
10'd512:panel_char=16'h9875;
10'd513:panel_char=16'h9762;
10'd514:panel_char=16'h52a0;
10'd515:panel_char=16'h8f7d;
10'd516:panel_char=16'h4e2d;
10'd576:panel_char=16'h624b;
10'd577:panel_char=16'h52bf;
10'd578:panel_char=16'h8c03;
10'd579:panel_char=16'h8bd5;
10'd640:panel_char=16'h8bf7;
10'd641:panel_char=16'h7a0d;
10'd642:panel_char=16'h505c;
10'd643:panel_char=16'h7247;
10'd644:panel_char=16'h523b;
10'd704:panel_char=16'h8bf7;
10'd705:panel_char=16'h5411;
10'd706:panel_char=16'h4e2d;
10'd707:panel_char=16'h592e;
10'd708:panel_char=16'h6536;
10'd709:panel_char=16'h624b;
10'd768:panel_char=16'h64cd;
10'd769:panel_char=16'h4f5c;
10'd770:panel_char=16'h6682;
10'd771:panel_char=16'h4e0d;
10'd772:panel_char=16'h53ef;
10'd773:panel_char=16'h7528;
10'd832:panel_char=16'h6682;
10'd833:panel_char=16'h65e0;
10'd834:panel_char=16'h753b;
10'd835:panel_char=16'h9762;
default:panel_char=16'h0020;endcase end endfunction
 reg [3:0] panel_message;
 wire [15:0] panel_bits; wire [15:0] panel_code=panel_char(panel_message,(nx-504)>>4);
 museum_panel_font_sync panel_font(.clk(clk),.glyph(panel_code),.row(ny[3:0]-4'd12),.bits(panel_bits));
 reg [9:0] local_x,local_y;
 reg panel_roi,panel_edge;
 reg [23:0] panel_ink;
 // Sixteen strings in one 1024x8 ROM; avoid a wide variable string mux.
 localparam [8191:0] TEXT=SWIPE_MODE ? {
  "S2 MOVE     ARM     EVENTS                                      ",
  "KEY2 BACKGROUND KEY3 REARM KEY4 VIEW                            ",
  "CENTER - SWIPE WHOLE HAND - HOLD AT END                         ",
  "LEFT RIGHT SELECT - UP BACK - DOWN ENTER                        ",
  "STREAM FAULT - RESET BOARD                                      ",
  "BACKGROUND WAIT - REMOVE HAND                                   ",
  "RETURN TO CENTER AND HOLD                                       ",
  "MOVING - STOP BRIEFLY TO CONFIRM                                ",
  "CENTER HAND - HOLD STILL TO ARM                                 ",
  "SEARCH - CENTER HAND                                            ",
  "CONFIRM - HOLD STILL                                            ",
  "ARMED - SWIPE WHOLE HAND                                        ",
  "MOVING - HOLD AT END TO CONFIRM                                 ",
  "RETURN - CENTER HAND AND HOLD                                   ",
  "INVALID TARGET - RECENTER                                       ",
  "WAIT - PAGE LOADING                                             "} : {
  "G1 POSE     ARM     EVENTS                                      ",
  "KEY2 BACKGROUND KEY3 CAPTURE KEY4 VIEW                          ",
  "WRIST AT CROSS - KEEP DISTANCE AND POSITION                     ",
  "LEFT RIGHT SELECT - UP BACK - DOWN ENTER                        ",
  "STREAM FAULT - RESET BOARD                                      ",
  "BACKGROUND WAIT - REMOVE HAND                                   ",
  "TOO SIMILAR - RETRY KEY3                                        ",
  "CAPTURING - HOLD STILL                                          ",
  "HOLD REQUESTED POSE THEN PRESS KEY3                             ",
  "CAPTURE N0 - FINGERS TO CAMERA                                  ",
  "CAPTURE N1 - OTHER NEUTRAL PALM ROLL                            ",
  "CAPTURE LEFT                                                    ",
  "CAPTURE RIGHT                                                   ",
  "CAPTURE UP                                                      ",
  "CAPTURE DOWN                                                    ",
  "READY - KEY4 RETURNS TO GALLERY                                 "};
 (* rom_style="bram_9k" *) reg [7:0] text_rom[0:1023];reg [7:0] text_q;
 integer k;
 initial begin for(k=0;k<1024;k=k+1)text_rom[k]=TEXT[(1023-k)*8 +:8];end
 reg [3:0] line_id;
 always @*begin
  line_id=0;
  case(ny[9:4])
   1:line_id=SWIPE_MODE ? 3 : 0;
   2:line_id=SWIPE_MODE ? (fault ? 4 : !background_ready ? 5 : !nav_ready ? 15 : stage==4 && (error==1 || error==2) ? 14 : stage<=4 ? 9+stage : 8) : 0;
   4:line_id=1;
   5:line_id=2;
   6:line_id=3;
   8:line_id=fault ? 4 : !background_ready ? 5 : SWIPE_MODE ? (stage==4 ? 6 : stage==3 ? 7 : 8) : error==2 ? 6 : collecting ? 7 : 8;
   9:line_id=SWIPE_MODE ? (stage<=4 ? 9+stage : 14) : stage<=6 ? 9+stage : 8;
   default:line_id=0;
  endcase
 end
 always @(posedge clk)text_q<=text_rom[{line_id,nx[8:3]}];
 wire [5:0] column=x[8:3];wire [2:0] gx=x[2:1],gy=y[3:1];
 reg [7:0] ch;reg [14:0] bits;
 wire text_zone=y<16 || (SWIPE_MODE && y>=16 && y<48) || (calibration && y>=64 && y<112) || (calibration && y>=128 && y<160);
 always @*begin
  ch=text_q;
  local_x=x>=472 ? x-472 : 0;local_y=y>=48 ? y-48 : 0;
  panel_roi=x>=472+13 && x<472+116 && y>=48+(ROI_Y0+4)/5 && y<48+(ROI_Y1+4)/5;
  panel_edge=panel_roi && (x==485 || x==587 || y==48+(ROI_Y0+4)/5 || y==48+(ROI_Y1+4)/5-1);
  panel_message=(source_fault===1'b1 || (fault && nav_overflow!==1'b1)) ? 1 : !recognition_enabled ? 0 : (nav_overflow===1'b1) ? 12 : (preparing===1'b1) ? 2 : !background_ready ? 3 : diagnostics ? 9 : !nav_ready ? 8 : stage==3 ? 6 : stage==2 ? 5 : stage==1 ? 10 : stage==4 ? (error==2 ? 11 : 7) : !preview_ready ? 13 : 4;


  panel_ink=fault ? 24'hff8080 : armed ? 24'h80ffb0 : !recognition_enabled ? 24'hd8e0e8 : 24'hffe080;
  if(y<16)begin
   if(column==8)ch=pose==0 ? "-" : pose==1 ? "N" : pose==2 ? "L" : pose==3 ? "R" : pose==4 ? "U" : "D";
   if(SWIPE_MODE && column==10)ch=stage+48;
   if(SWIPE_MODE && column==36)ch=error+48;
   if(column==16)ch=armed ? "1" : "0";
   if(column>=27 && column<35)begin
    ch=(event_sequence>>((34-column)*4))&15;
    ch=ch<10 ? ch+48 : ch+55;
   end
  end
  bits=glyph(ch);
  rgb=calibration && !INTEGRATED_STYLE ? 24'h101824 : base_rgb;
  if(calibration && x>=160 && x<480 && y>=160 && y<400)begin
   rgb=background_ready && mask_q ? 24'h90d0a0 : INTEGRATED_STYLE ? 24'he4eadc : 24'h050809;
   if(x==192 || x==447 || y==160+ROI_Y0/2 || y==160+ROI_Y1/2-1)rgb=24'h304860;
   if((x>=308 && x<=332 && (y==279 || y==280)) ||
      (y>=268 && y<=292 && (x==319 || x==320)))rgb=24'hffcc00;
  end
  if(!calibration && (!INTEGRATED_STYLE || preview_enable) && x>=464 && x<624 && y>=344 && y<464)begin
   rgb=preview_ready ? preview_color : INTEGRATED_STYLE ? 24'he4eadc : 24'h050809;
   if(x==464 || x==623 || y==344 || y==463)
    rgb=fault ? 24'hc03030 : preview_ready ? 24'h60b8c8 : 24'h304860;
   if(((x==480 || x==607) && y>=344+ROI_Y0/4 && y<=344+ROI_Y1/4-1) ||
      ((y==344+ROI_Y0/4 || y==344+ROI_Y1/4-1) && x>=480 && x<=607))rgb=24'h304860;
   if((x>=538 && x<=550 && (y==403 || y==404)) ||
      (y>=398 && y<=410 && (x==543 || x==544)))rgb=24'hffcc00;
  end
  // Start zone uses source coordinates x256..384/y184..296. Green cursor
  // follows the measured region; it disappears on invalid/stale samples.
  if(SWIPE_MODE)begin
   if(calibration && (((x==288 || x==352) && y>=252 && y<=308) ||
                     ((y==252 || y==308) && x>=288 && x<=352)))rgb=24'hffcc00;
   if(!calibration && (!INTEGRATED_STYLE || preview_enable) && (((x==528 || x==560) && y>=390 && y<=418) ||
                      ((y==390 || y==418) && x>=528 && x<=560)))rgb=24'hffcc00;
   if(target_visible && (!INTEGRATED_STYLE || calibration || preview_enable) && ((x>=cursor_x-2 && x<=cursor_x+2 && y==cursor_y) ||
       (y>=cursor_y-2 && y<=cursor_y+2 && x==cursor_x)))rgb=24'h20ff60;
  end
  if(text_zone && !INTEGRATED_STYLE)begin
   rgb=fault ? 24'h601818 : 24'h102030;
   if(x<512 && gx<3 && gy<5 && bits[14-gy*3-gx])rgb=24'he0e8f0;
  end
  if(INTEGRATED_STYLE)begin
   rgb=base_rgb;
   if(preview_enable && x>=504 && x<632 && y>=8 && y<120)begin
    rgb=calibration ? (background_ready && mask_q ? 24'h90d0a0 : 24'h101820) : preview_ready ? preview_color : 24'he4eadc;
    if(x==504 || x==631 || y==8 || y==119)rgb=24'h8c8a7e;
    // Sample-mapped tracker center region: raw cx=256..384, cy=184..296.
    // Mirrored 80x60 sampling yields local u=46..79, v=42..71.
    // Four 6-pixel corner arms; inclusive 34x30 footprint, one-pixel stroke.
    if(preview_ready && !calibration && roi_corner_hit)
      rgb=24'hf5e9a8;

   end
   if(preview_enable && x>=504 && x<632 && y>=124 && y<140)begin
    rgb=24'hf2ede3;
    if(panel_bits[15-(x-504)%16])rgb=fault ? 24'h9a3030 : 24'h243938;
   end
  end
  if(!de || rst)rgb=0;
 end
endmodule

module museum_panel_font_sync(input clk,input [15:0] glyph,input [3:0] row,output reg [15:0] bits);
 (* ram_style="bram_9k" *) reg [15:0] memory[0:1023];
 reg [5:0] slot;
 integer i;
 always @* begin case(glyph)
16'd32:slot=6'd0;
16'd19981:slot=6'd1;
16'd20013:slot=6'd2;
16'd20102:slot=6'd3;
16'd20197:slot=6'd4;
16'd20316:slot=6'd5;
16'd20572:slot=6'd6;
16'd20687:slot=6'd7;
16'd20808:slot=6'd8;
16'd20934:slot=6'd9;
16'd21035:slot=6'd10;
16'd21051:slot=6'd11;
16'd21152:slot=6'd12;
16'd21160:slot=6'd13;
16'd21183:slot=6'd14;
16'd21487:slot=6'd15;
16'd21521:slot=6'd16;
16'd22238:slot=6'd17;
16'd22270:slot=6'd18;
16'd22312:slot=6'd19;
16'd22791:slot=6'd20;
16'd22830:slot=6'd21;
16'd23558:slot=6'd22;
16'd23621:slot=6'd23;
16'd24120:slot=6'd24;
16'd24320:slot=6'd25;
16'd24322:slot=6'd26;
16'd25163:slot=6'd27;
16'd25805:slot=6'd28;
16'd25910:slot=6'd29;
16'd26080:slot=6'd30;
16'd26242:slot=6'd31;
16'd26426:slot=6'd32;
16'd27491:slot=6'd33;
16'd27969:slot=6'd34;
16'd28369:slot=6'd35;
16'd29255:slot=6'd36;
16'd29992:slot=6'd37;
16'd30011:slot=6'd38;
16'd30456:slot=6'd39;
16'd31227:slot=6'd40;
16'd31245:slot=6'd41;
16'd31283:slot=6'd42;
16'd35272:slot=6'd43;
16'd35782:slot=6'd44;
16'd35797:slot=6'd45;
16'd35831:slot=6'd46;
16'd35843:slot=6'd47;
16'd36733:slot=6'd48;
16'd38754:slot=6'd49;
16'd39029:slot=6'd50;
16'd39044:slot=6'd51;
default:slot=6'd0;
 endcase end
 initial begin for(i=0;i<1024;i=i+1)memory[i]=0;
memory[17]=16'hfffe;
memory[18]=16'h0080;
memory[19]=16'h0100;
memory[20]=16'h0100;
memory[21]=16'h0300;
memory[22]=16'h0540;
memory[23]=16'h0930;
memory[24]=16'h1108;
memory[25]=16'h2104;
memory[26]=16'h4102;
memory[27]=16'h8100;
memory[28]=16'h0100;
memory[29]=16'h0100;
memory[34]=16'h0180;
memory[35]=16'h0180;
memory[36]=16'h3ffc;
memory[37]=16'h2184;
memory[38]=16'h2184;
memory[39]=16'h2184;
memory[40]=16'h2184;
memory[41]=16'h3ffc;
memory[42]=16'h2184;
memory[43]=16'h0180;
memory[44]=16'h0180;
memory[45]=16'h0180;
memory[49]=16'h7ffc;
memory[50]=16'h001c;
memory[51]=16'h0030;
memory[52]=16'h00c0;
memory[53]=16'h0180;
memory[54]=16'h0100;
memory[55]=16'h0100;
memory[56]=16'h0100;
memory[57]=16'h0100;
memory[58]=16'h0100;
memory[59]=16'h0100;
memory[60]=16'h0100;
memory[61]=16'h1e00;
memory[65]=16'h0408;
memory[66]=16'h4208;
memory[67]=16'h4208;
memory[68]=16'h4108;
memory[69]=16'h4008;
memory[70]=16'h4008;
memory[71]=16'h4008;
memory[72]=16'h4010;
memory[73]=16'h4210;
memory[74]=16'h5c38;
memory[75]=16'h70cc;
memory[76]=16'hc186;
memory[77]=16'h0602;
memory[81]=16'h1100;
memory[82]=16'h1200;
memory[83]=16'h23fc;
memory[84]=16'h2480;
memory[85]=16'h6480;
memory[86]=16'h68f8;
memory[87]=16'ha080;
memory[88]=16'ha080;
memory[89]=16'h2080;
memory[90]=16'h20fc;
memory[91]=16'h2080;
memory[92]=16'h2080;
memory[93]=16'h2080;
memory[98]=16'h0840;
memory[99]=16'h1ffe;
memory[100]=16'h1000;
memory[101]=16'h33f8;
memory[102]=16'h3208;
memory[103]=16'h73f8;
memory[104]=16'h5000;
memory[105]=16'h17fe;
memory[106]=16'h1402;
memory[107]=16'h13f8;
memory[108]=16'h1060;
memory[109]=16'h11c0;
memory[114]=16'h0980;
memory[115]=16'h1bf0;
memory[116]=16'h1630;
memory[117]=16'h17fc;
memory[118]=16'h3244;
memory[119]=16'h73fc;
memory[120]=16'h51cc;
memory[121]=16'h16f8;
memory[122]=16'h13e8;
memory[123]=16'h16ec;
memory[124]=16'h1326;
memory[125]=16'h1620;
memory[126]=16'h01c0;
memory[129]=16'h0900;
memory[130]=16'h1100;
memory[131]=16'h1ffc;
memory[132]=16'h2100;
memory[133]=16'h4100;
memory[134]=16'h0100;
memory[135]=16'h7ffe;
memory[136]=16'h0440;
memory[137]=16'h0440;
memory[138]=16'h0842;
memory[139]=16'h0842;
memory[140]=16'h3042;
memory[141]=16'hc07c;
memory[145]=16'h0240;
memory[146]=16'h8420;
memory[147]=16'h47fe;
memory[148]=16'h2c20;
memory[149]=16'h0c20;
memory[150]=16'h17fc;
memory[151]=16'h0420;
memory[152]=16'h2420;
memory[153]=16'h47fc;
memory[154]=16'h4420;
memory[155]=16'hc420;
memory[156]=16'h87fe;
memory[157]=16'h0400;
memory[162]=16'h3f84;
memory[163]=16'h21a4;
memory[164]=16'h21a4;
memory[165]=16'h3fa4;
memory[166]=16'h21a4;
memory[167]=16'h0824;
memory[168]=16'h3fa4;
memory[169]=16'h09a4;
memory[170]=16'h19a4;
memory[171]=16'h1184;
memory[172]=16'h3104;
memory[173]=16'h6f3c;
memory[177]=16'h0804;
memory[178]=16'h0c04;
memory[179]=16'hffa4;
memory[180]=16'h1024;
memory[181]=16'h2224;
memory[182]=16'h4424;
memory[183]=16'h7d24;
memory[184]=16'h1a24;
memory[185]=16'h3624;
memory[186]=16'h6424;
memory[187]=16'hca04;
memory[188]=16'h3104;
memory[189]=16'h60bc;
memory[193]=16'h1000;
memory[194]=16'h1000;
memory[195]=16'h107c;
memory[196]=16'h7e44;
memory[197]=16'h1244;
memory[198]=16'h1244;
memory[199]=16'h1244;
memory[200]=16'h1244;
memory[201]=16'h1244;
memory[202]=16'h3244;
memory[203]=16'h2244;
memory[204]=16'h227c;
memory[205]=16'h5e44;
memory[209]=16'h0040;
memory[210]=16'h3e40;
memory[211]=16'h0040;
memory[212]=16'h01fc;
memory[213]=16'h0044;
memory[214]=16'h7f44;
memory[215]=16'h1044;
memory[216]=16'h1444;
memory[217]=16'h24c4;
memory[218]=16'h2684;
memory[219]=16'h2e84;
memory[220]=16'h7304;
memory[221]=16'h023c;
memory[226]=16'h0840;
memory[227]=16'h3ff8;
memory[228]=16'h08d8;
memory[229]=16'h1fd8;
memory[230]=16'h38ca;
memory[231]=16'h092e;
memory[232]=16'h3a0c;
memory[233]=16'h0300;
memory[234]=16'h3ff8;
memory[235]=16'h0208;
memory[236]=16'h0608;
memory[237]=16'h1cf8;
memory[238]=16'h3000;
memory[241]=16'hfffc;
memory[242]=16'h0010;
memory[243]=16'h0010;
memory[244]=16'h3f10;
memory[245]=16'h2110;
memory[246]=16'h2110;
memory[247]=16'h2110;
memory[248]=16'h2110;
memory[249]=16'h3f10;
memory[250]=16'h2010;
memory[251]=16'h0010;
memory[252]=16'h0010;
memory[253]=16'h01e0;
memory[257]=16'h0200;
memory[258]=16'h0400;
memory[259]=16'h7ff8;
memory[260]=16'h4008;
memory[261]=16'h4008;
memory[262]=16'h4fc8;
memory[263]=16'h4848;
memory[264]=16'h4848;
memory[265]=16'h4848;
memory[266]=16'h4fc8;
memory[267]=16'h4808;
memory[268]=16'h4008;
memory[269]=16'h4078;
memory[274]=16'h3ffc;
memory[275]=16'h2004;
memory[276]=16'h2004;
memory[277]=16'h27e4;
memory[278]=16'h2424;
memory[279]=16'h2424;
memory[280]=16'h2424;
memory[281]=16'h2424;
memory[282]=16'h27e4;
memory[283]=16'h2424;
memory[284]=16'h2004;
memory[285]=16'h3ffc;
memory[286]=16'h2004;
memory[289]=16'h7ffc;
memory[290]=16'h4204;
memory[291]=16'h47f4;
memory[292]=16'h4c24;
memory[293]=16'h5244;
memory[294]=16'h43c4;
memory[295]=16'h7c3c;
memory[296]=16'h4704;
memory[297]=16'h40c4;
memory[298]=16'h4e04;
memory[299]=16'h41e4;
memory[300]=16'h7ffc;
memory[301]=16'h4004;
memory[306]=16'h0200;
memory[307]=16'h0200;
memory[308]=16'h7ffe;
memory[309]=16'h0400;
memory[310]=16'h0c40;
memory[311]=16'h1840;
memory[312]=16'h1bfc;
memory[313]=16'h3840;
memory[314]=16'h5840;
memory[315]=16'h1840;
memory[316]=16'h1840;
memory[317]=16'h1ffe;
memory[320]=16'h0800;
memory[321]=16'h1800;
memory[322]=16'h3ff8;
memory[323]=16'h3818;
memory[324]=16'h4460;
memory[325]=16'h83c0;
memory[326]=16'h0c60;
memory[327]=16'hf01e;
memory[328]=16'h3ff8;
memory[329]=16'h2108;
memory[330]=16'h3ff8;
memory[331]=16'h2108;
memory[332]=16'h3ff8;
memory[333]=16'h2008;
memory[338]=16'h0180;
memory[339]=16'h0180;
memory[340]=16'h1ff8;
memory[341]=16'h1188;
memory[342]=16'h1188;
memory[343]=16'h1188;
memory[344]=16'h7ffe;
memory[345]=16'h0180;
memory[346]=16'h0240;
memory[347]=16'h0660;
memory[348]=16'h1838;
memory[349]=16'h700e;
memory[354]=16'h1880;
memory[355]=16'h19fc;
memory[356]=16'h5a0c;
memory[357]=16'h3cb8;
memory[358]=16'h38e0;
memory[359]=16'h1f08;
memory[360]=16'h1ffe;
memory[361]=16'h3908;
memory[362]=16'h3988;
memory[363]=16'h5888;
memory[364]=16'h1818;
memory[365]=16'h1878;
memory[369]=16'h3ff8;
memory[370]=16'h2008;
memory[371]=16'h2008;
memory[372]=16'h3ff8;
memory[373]=16'h2008;
memory[374]=16'h2080;
memory[375]=16'h3ffc;
memory[376]=16'h2080;
memory[377]=16'h2ff8;
memory[378]=16'h2808;
memory[379]=16'h4808;
memory[380]=16'h4ff8;
memory[381]=16'h8808;
memory[386]=16'h1998;
memory[387]=16'h0db0;
memory[388]=16'h3ffc;
memory[389]=16'h2004;
memory[390]=16'h2ff4;
memory[391]=16'h0810;
memory[392]=16'h0ff0;
memory[393]=16'h0180;
memory[394]=16'h3ffc;
memory[395]=16'h318c;
memory[396]=16'h31b8;
memory[397]=16'h0180;
memory[402]=16'h3ffc;
memory[403]=16'h0430;
memory[404]=16'h0420;
memory[405]=16'h0420;
memory[406]=16'h0420;
memory[407]=16'h7ffe;
memory[408]=16'h0430;
memory[409]=16'h0420;
memory[410]=16'h0c20;
memory[411]=16'h0820;
memory[412]=16'h1820;
memory[413]=16'h2020;
memory[418]=16'h1ff8;
memory[419]=16'h1018;
memory[420]=16'h1018;
memory[421]=16'h1ff8;
memory[422]=16'h1006;
memory[423]=16'h1ffc;
memory[425]=16'h0430;
memory[426]=16'h7ffe;
memory[427]=16'h0c30;
memory[428]=16'h1830;
memory[429]=16'h3030;
memory[434]=16'h00fc;
memory[435]=16'h3fe0;
memory[436]=16'h0180;
memory[437]=16'h0180;
memory[438]=16'h3ffc;
memory[439]=16'h0180;
memory[440]=16'h0180;
memory[441]=16'h7ffe;
memory[442]=16'h0180;
memory[443]=16'h0180;
memory[444]=16'h0180;
memory[445]=16'h0f00;
memory[449]=16'h23f8;
memory[450]=16'h2208;
memory[451]=16'hfbf8;
memory[452]=16'h2000;
memory[453]=16'h27bc;
memory[454]=16'h3ca4;
memory[455]=16'h67bc;
memory[456]=16'ha040;
memory[457]=16'h27fe;
memory[458]=16'h20e0;
memory[459]=16'h2150;
memory[460]=16'h2248;
memory[461]=16'hec46;
memory[465]=16'h0880;
memory[466]=16'h0900;
memory[467]=16'h49fe;
memory[468]=16'h4b08;
memory[469]=16'h4b08;
memory[470]=16'h4d08;
memory[471]=16'h4990;
memory[472]=16'h4890;
memory[473]=16'h58f0;
memory[474]=16'h6860;
memory[475]=16'h48e0;
memory[476]=16'h0998;
memory[477]=16'h0e06;
memory[481]=16'h7ffc;
memory[482]=16'h0100;
memory[483]=16'h0100;
memory[484]=16'h0100;
memory[485]=16'h0200;
memory[486]=16'hfffe;
memory[487]=16'h0200;
memory[488]=16'h0480;
memory[489]=16'h0480;
memory[490]=16'h0882;
memory[491]=16'h1082;
memory[492]=16'h6082;
memory[493]=16'hc0fc;
memory[497]=16'h100c;
memory[498]=16'hfef0;
memory[499]=16'h6880;
memory[500]=16'h7efe;
memory[501]=16'h0888;
memory[502]=16'hff08;
memory[503]=16'h0800;
memory[504]=16'h1ff0;
memory[505]=16'h1010;
memory[506]=16'h1ff0;
memory[507]=16'h1010;
memory[508]=16'h1ff0;
memory[509]=16'h1010;
memory[513]=16'h11f0;
memory[514]=16'h1110;
memory[515]=16'h7d10;
memory[516]=16'h1110;
memory[517]=16'h1110;
memory[518]=16'h3910;
memory[519]=16'h3510;
memory[520]=16'h5110;
memory[521]=16'h5110;
memory[522]=16'h5112;
memory[523]=16'h1212;
memory[524]=16'h1212;
memory[525]=16'h141c;
memory[530]=16'h3ffc;
memory[531]=16'h0080;
memory[532]=16'h0080;
memory[533]=16'h1880;
memory[534]=16'h1880;
memory[535]=16'h18fc;
memory[536]=16'h1880;
memory[537]=16'h1880;
memory[538]=16'h1880;
memory[539]=16'h1880;
memory[540]=16'h1880;
memory[541]=16'h7ffe;
memory[545]=16'h40c0;
memory[546]=16'h2ffc;
memory[547]=16'h1180;
memory[548]=16'h4310;
memory[549]=16'h6408;
memory[550]=16'h2ff8;
memory[551]=16'h0004;
memory[552]=16'h2250;
memory[553]=16'h2250;
memory[554]=16'h2252;
memory[555]=16'h4652;
memory[556]=16'h4c52;
memory[557]=16'h585c;
memory[560]=16'h4000;
memory[561]=16'h23f8;
memory[562]=16'h1208;
memory[563]=16'h03c8;
memory[564]=16'h4248;
memory[565]=16'h2ffc;
memory[566]=16'h0804;
memory[567]=16'h03f8;
memory[568]=16'h2208;
memory[569]=16'h23f8;
memory[570]=16'h2208;
memory[571]=16'h43f8;
memory[572]=16'h4208;
memory[573]=16'h4238;
memory[577]=16'h1040;
memory[578]=16'h1040;
memory[579]=16'h1040;
memory[580]=16'h1040;
memory[581]=16'h1ffe;
memory[582]=16'h1000;
memory[583]=16'h1000;
memory[584]=16'h1fe0;
memory[585]=16'h1020;
memory[586]=16'h1020;
memory[587]=16'h2020;
memory[588]=16'h2020;
memory[589]=16'h4020;
memory[593]=16'h3ffc;
memory[594]=16'h2104;
memory[595]=16'h2104;
memory[596]=16'h2104;
memory[597]=16'h3ffc;
memory[598]=16'h2104;
memory[599]=16'h2104;
memory[600]=16'h2104;
memory[601]=16'h3ffc;
memory[602]=16'h2104;
memory[603]=16'h6104;
memory[604]=16'h4104;
memory[605]=16'h813c;
memory[609]=16'hfffe;
memory[611]=16'h4fe4;
memory[612]=16'h4924;
memory[613]=16'h4924;
memory[614]=16'h4fe4;
memory[615]=16'h4924;
memory[616]=16'h4924;
memory[617]=16'h4fe4;
memory[618]=16'h4824;
memory[619]=16'h4004;
memory[620]=16'h7ffc;
memory[621]=16'h0004;
memory[625]=16'h11fc;
memory[626]=16'h1104;
memory[627]=16'h7d04;
memory[628]=16'h1104;
memory[629]=16'h11fc;
memory[630]=16'h3904;
memory[631]=16'h3504;
memory[632]=16'h51fc;
memory[633]=16'h5104;
memory[634]=16'h1104;
memory[635]=16'h1104;
memory[636]=16'h11fc;
memory[637]=16'h1104;
memory[642]=16'h0c40;
memory[643]=16'h78fc;
memory[644]=16'h198c;
memory[645]=16'h1b78;
memory[646]=16'h7c60;
memory[647]=16'h1be0;
memory[648]=16'h3c7e;
memory[649]=16'h3e84;
memory[650]=16'h790c;
memory[651]=16'h5a38;
memory[652]=16'h18e0;
memory[653]=16'h1b80;
memory[657]=16'h0e22;
memory[658]=16'h7124;
memory[659]=16'h10a8;
memory[660]=16'h1020;
memory[661]=16'h7ffe;
memory[662]=16'h1102;
memory[663]=16'h39fe;
memory[664]=16'h3d02;
memory[665]=16'h3502;
memory[666]=16'h51fe;
memory[667]=16'h5102;
memory[668]=16'h1102;
memory[669]=16'h111e;
memory[674]=16'h1c80;
memory[675]=16'h79f8;
memory[676]=16'h1210;
memory[677]=16'h11fc;
memory[678]=16'h7c04;
memory[679]=16'h11fc;
memory[680]=16'h3c04;
memory[681]=16'h37fc;
memory[682]=16'h7040;
memory[683]=16'h53ac;
memory[684]=16'h159a;
memory[685]=16'h10f0;
memory[689]=16'h4840;
memory[690]=16'h48fe;
memory[691]=16'h4900;
memory[692]=16'h4960;
memory[693]=16'h4a1c;
memory[695]=16'h3ff8;
memory[696]=16'h2008;
memory[697]=16'h2108;
memory[698]=16'h210a;
memory[699]=16'h0382;
memory[700]=16'h0e82;
memory[701]=16'hf0fc;
memory[706]=16'h13fc;
memory[707]=16'h1b04;
memory[708]=16'h0b04;
memory[709]=16'h0304;
memory[710]=16'h7304;
memory[711]=16'h1304;
memory[712]=16'h13fc;
memory[713]=16'h1304;
memory[714]=16'h1400;
memory[715]=16'h1d98;
memory[716]=16'h1b0c;
memory[717]=16'h1606;
memory[721]=16'h4028;
memory[722]=16'h2024;
memory[723]=16'h3020;
memory[724]=16'h07fe;
memory[725]=16'h0020;
memory[726]=16'he020;
memory[727]=16'h27e0;
memory[728]=16'h2120;
memory[729]=16'h2120;
memory[730]=16'h2912;
memory[731]=16'h39d2;
memory[732]=16'h3e1a;
memory[733]=16'h400c;
memory[738]=16'h2040;
memory[739]=16'h17fe;
memory[740]=16'h1840;
memory[741]=16'h03fc;
memory[742]=16'h7040;
memory[743]=16'h17fe;
memory[744]=16'h120c;
memory[745]=16'h13fc;
memory[746]=16'h120c;
memory[747]=16'h17fc;
memory[748]=16'h1a0c;
memory[749]=16'h1238;
memory[753]=16'h47fc;
memory[754]=16'h2404;
memory[755]=16'h1444;
memory[756]=16'h05f4;
memory[757]=16'he444;
memory[758]=16'h27fc;
memory[759]=16'h2404;
memory[760]=16'h25f4;
memory[761]=16'h2d14;
memory[762]=16'h3514;
memory[763]=16'h49f4;
memory[764]=16'h0904;
memory[765]=16'h103c;
memory[769]=16'h0858;
memory[770]=16'h7f4c;
memory[771]=16'h0840;
memory[772]=16'hfffe;
memory[773]=16'h1040;
memory[774]=16'hffc4;
memory[775]=16'h2048;
memory[776]=16'h4828;
memory[777]=16'h7f30;
memory[778]=16'h0822;
memory[779]=16'h0f72;
memory[780]=16'hf8d2;
memory[781]=16'h090c;
memory[786]=16'h7ffe;
memory[787]=16'h0100;
memory[788]=16'h0100;
memory[789]=16'h3ffc;
memory[790]=16'h2664;
memory[791]=16'h27e4;
memory[792]=16'h2664;
memory[793]=16'h27e4;
memory[794]=16'h2664;
memory[795]=16'h2664;
memory[796]=16'h3ffc;
memory[797]=16'h2004;
memory[802]=16'h7ffe;
memory[803]=16'h0180;
memory[804]=16'h0100;
memory[805]=16'h1ff8;
memory[806]=16'h1008;
memory[807]=16'h1188;
memory[808]=16'h1188;
memory[809]=16'h1188;
memory[810]=16'h1188;
memory[811]=16'h03e0;
memory[812]=16'h0e38;
memory[813]=16'h7004;
memory[817]=16'hfbfe;
memory[818]=16'h1840;
memory[819]=16'h5040;
memory[820]=16'h31fc;
memory[821]=16'h3104;
memory[822]=16'hfd24;
memory[823]=16'h2524;
memory[824]=16'h2924;
memory[825]=16'h2124;
memory[826]=16'h2164;
memory[827]=16'h20f0;
memory[828]=16'h218c;
memory[829]=16'he606;
 end
 always @(posedge clk)bits<=memory[{slot,row}];
endmodule

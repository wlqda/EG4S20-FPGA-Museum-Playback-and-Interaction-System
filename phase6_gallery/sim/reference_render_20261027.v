// Frozen pre-ROM compositor from 07e97a4, for latency/pixel equivalence.
// One-cycle pixel compositor, matching the preserved phase4 HDMI pipeline.
module museum_render_reference(input clk,rst,input [9:0] x,y,input active,
 input [23:0] base_rgb,input [3:0] page,input [1:0] focus,
 input [3:0] photo_index,input [1:0] zoom,input [4:0] fade_level,
 input editing,autoplay,input [5:0] interval_seconds,
 input [8:0] volume,brightness,input image_mode,playing,paused,screen_visible,frame_valid,
 input [7:0] media_error,output reg [23:0] out_rgb);
 localparam [23:0] IVORY=24'hf4eee4,RED=24'ha63826,INK=24'h534b40;
 reg [23:0] color;reg [15:0] glyph;reg [3:0] row,col;
 reg text_on;reg [9:0] left_edge,top_edge,right_edge,bottom_edge;reg [7:0] number;
 reg [3:0] digit;reg [2:0] position;reg [1:0] setting_row;
 wire [15:0] bits;
 wire [12:0] fade_r=base_rgb[23:16]*fade_level;
 wire [12:0] fade_g=base_rgb[15:8]*fade_level;
 wire [12:0] fade_b=base_rgb[7:0]*fade_level;
 museum_phase6_font font(.glyph(glyph),.row(row),.bits(bits));
 function [15:0] hexchar;input [3:0] value;begin hexchar=value<10 ? 16'd48+value : 16'd55+value;end endfunction
 function [15:0] loading_char;input [3:0] p;begin
  case(p)0:loading_char=16'h52a0;1:loading_char=16'h8f7d;2:loading_char=16'h4e2d;default:loading_char=16'h0020;endcase
 end endfunction
 function [15:0] error_char;input [3:0] p;begin
  case(p)0:error_char=16'h8bf7;1:error_char=16'h68c0;2:error_char=16'h67e5;3:error_char=16'h0054;4:error_char=16'h0046;5:error_char=16'h5361;6:error_char=16'h8d44;7:error_char=16'h6e90;default:error_char=16'h0020;endcase
 end endfunction
 function [15:0] video_char;input [3:0] p;begin
  case(p)0:video_char=16'h5f71;1:video_char=16'h50cf;2:video_char=16'h5c55;3:video_char=16'h793a;default:video_char=16'h0020;endcase
 end endfunction
 always @* begin
  color=base_rgb;glyph=32;row=y[3:0];col=x[3:0];text_on=0;
  left_edge=page==0 ? (focus==0 ? 10'd26 : focus==1 ? 10'd227 : 10'd428) : 10'd26+{8'd0,focus}*10'd152;top_edge=0;right_edge=0;bottom_edge=0;number=0;digit=0;position=0;setting_row=0;
  if(image_mode && !frame_valid || media_error!=0)begin
   color=IVORY;
   if(x<12)color=RED;
   if(y>=224 && y<240 && x>=232 && x<408)begin
    text_on=1;row=y-224;col=x[3:0]-4'd8;
    if(media_error!=0)glyph=error_char((x-232)>>4);
    else glyph=loading_char((x-232)>>4);
   end
   if(media_error!=0 && y>=256 && y<272 && x>=304 && x<336)begin
    text_on=1;row=y-256;col=x[3:0];glyph=x<320 ? hexchar(media_error[7:4]) : hexchar(media_error[3:0]);
   end
  end else if(!image_mode)begin
   if(y<60 || y>=420)color=IVORY;
   if(y==59 || y==420)color=RED;
   if(x>=24 && x<152 && y>=16 && y<48)begin
    text_on=1;glyph=video_char((x-24)>>5);col=(x-24)>>1;row=(y-16)>>1;
   end
   if(x>=24 && x<56 && y>=440 && y<456)begin
    text_on=1;row=y-440;col=x[3:0]-4'd8;
    if(paused)glyph=x<40 ? 16'h6682 : 16'h505c;
    else glyph=x<40 ? 16'h64ad : 16'h653e;
   end
  end else if(page==7)begin
   color=screen_visible ? {fade_r[11:4],fade_g[11:4],fade_b[11:4]} : 24'h171614;
   if(zoom!=0 && y>=22 && y<38 && x>=560 && x<592)begin
    text_on=1;row=y-22;col=(x-560)&15;glyph=x<576 ? (zoom==1 ? "2" : "4") : "X";
   end
  end else if(screen_visible)begin
   if(page==0 || page==1)begin
    top_edge=page==0 ? 10'd160 : 10'd141;
    right_edge=left_edge+(page==0 ? 10'd186 : 10'd132);
    bottom_edge=page==0 ? 10'd400 : 10'd405;
    if(((x>=left_edge && x<left_edge+10'd2 || x>=right_edge-10'd2 && x<right_edge) && y>=top_edge && y<bottom_edge) ||
       ((y>=top_edge && y<top_edge+10'd2 || y>=bottom_edge-10'd2 && y<bottom_edge) && x>=left_edge && x<right_edge))color=RED;
   end
   if(page==5)begin
    top_edge=10'd141+{8'd0,focus}*10'd66;
    if(((x>=26 && x<28 || x>=612 && x<614) && y>=top_edge && y<top_edge+54) ||
       ((y>=top_edge && y<top_edge+2 || y>=top_edge+52 && y<top_edge+54) && x>=26 && x<614))color=RED;
    if(editing && x>=496 && x<600 && y>=top_edge+8 && y<top_edge+46)color=RED;
    if(x>=504 && x<600)begin
     if(y>=160 && y<176)begin setting_row=0;number=(volume*100)>>8;text_on=1;row=y-160;end
     if(y>=226 && y<242)begin setting_row=1;number=(brightness*100)>>8;text_on=1;row=y-226;end
     if(y>=292 && y<308)begin setting_row=2;number=interval_seconds;text_on=1;row=y-292;end
     if(y>=358 && y<374)begin setting_row=3;text_on=1;row=y-358;end
     if(text_on)begin
      position=(x-504)>>4;col=(x-504);
      if(setting_row==3)begin
       if(position==2)glyph=autoplay ? 16'h5f00 : 16'h5173;
       else if(position==3)glyph=autoplay ? 16'h542f : 16'h95ed;
      end else begin
       case(position)
        0:glyph=number>=100 ? 16'd49 : 16'd32;
        1:glyph=number>=10 ? 16'd48+(number/10)%10 : 16'd32;
        2:glyph=16'd48+number%10;
        3:glyph=setting_row==2 ? 16'h79d2 : 16'd37;
        default:glyph=32;
       endcase
      end
     end
    end
   end
  end
  if(text_on && bits[15-col])color=page==5 && editing && setting_row==focus ? 24'hffffff : INK;
  if(!active)color=0;
 end
 always @(posedge clk)begin if(rst)out_rgb<=0;else out_rgb<=color;end
endmodule

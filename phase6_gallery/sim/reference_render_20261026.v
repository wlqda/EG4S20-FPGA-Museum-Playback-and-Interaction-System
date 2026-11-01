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
 reg text_on;reg [9:0] left_edge,top_edge;reg [7:0] number;
 reg [3:0] digit;reg [2:0] position;reg [1:0] setting_row;
 wire [15:0] bits;
 wire [12:0] fade_r=base_rgb[23:16]*fade_level;
 wire [12:0] fade_g=base_rgb[15:8]*fade_level;
 wire [12:0] fade_b=base_rgb[7:0]*fade_level;
 wire [1:0] photo_owner=photo_index<3 ? 0 : photo_index<6 ? 1 : photo_index<10 ? 2 : 3;
 museum_phase6_font font(.glyph(glyph),.row(row),.bits(bits));
 wire [1:0] logo_color;
 wire [8:0] logo_x=x-10'd32;
 wire [5:0] logo_y=y-10'd10;
 museum_gallery_logo logo(.x(logo_x),.y(logo_y),.color(logo_color));
 function [15:0] title_char;input [1:0] item;input [2:0] pos;begin
  title_char=32;
  case(item)
   0:case(pos)0:title_char=16'h9752;1:title_char=16'h94dc;2:title_char=16'h65b9;3:title_char=16'h9f0e;endcase
   1:case(pos)0:title_char=16'h9752;1:title_char=16'h82b1;2:title_char=16'h74f7;3:title_char=16'h74f6;endcase
   2:case(pos)0:title_char=16'h7389;1:title_char=16'h74a7;endcase
   3:case(pos)0:title_char=16'h9676;1:title_char=16'h4f8d;2:title_char=16'h5973;3:title_char=16'h4fd1;endcase
  endcase
 end endfunction
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
  left_edge=page==0 ? (focus==0 ? 10'd24 : focus==1 ? 10'd225 : 10'd426) : 24+{8'd0,focus}*150;top_edge=0;number=0;digit=0;position=0;setting_row=0;
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
   if(y<54 || y>=414)color=IVORY;
   if(y==53 || y==414)color=RED;
   if(y>=10 && y<43 && x>=32 && x<322 && logo_color!=0)
    color=logo_color==2 ? 24'hc72832 : 24'h1c2c4e;
   if(y>=432 && y<448 && x>=32 && x<96)begin
    text_on=1;row=y-432;col=(x-32)&15;glyph=title_char(photo_owner,(x-32)>>4);
   end
   if(y>=432 && y<448 && x>=520 && x<616)begin
    text_on=1;row=y-432;col=(x-520)&15;
    case((x-520)>>4)
     0:glyph=photo_index==9 || photo_index==10 || photo_index==11 || photo_index==12 ? "1" : "0";
     1:glyph="0"+(photo_index+1)%10;
     2:glyph="/";
     3:glyph="1";
     4:glyph="3";
     5:glyph=zoom==1 ? "2" : zoom==2 ? "4" : " ";
     default:glyph=32;
    endcase
   end
   if(zoom!=0 && y>=22 && y<38 && x>=560 && x<592)begin
    text_on=1;row=y-22;col=(x-560)&15;glyph=x<576 ? (zoom==1 ? "2" : "4") : "X";
   end
  end else if(screen_visible)begin
   if(page==0 || page==1)begin
    top_edge=page==0 ? 147 : 129;
    if(((x>=left_edge-4 && x<left_edge-2 || x>=left_edge+(page==0 ? 192 : 142) && x<left_edge+(page==0 ? 194 : 144)) && y>=top_edge && y<405) ||
       ((y>=top_edge && y<top_edge+2 || y>=403 && y<405) && x>=left_edge-4 && x<left_edge+(page==0 ? 194 : 144)))color=RED;
   end
   if(page==5)begin
    top_edge=131+{8'd0,focus}*57;
    if(((x>=24 && x<26 || x>=614 && x<616) && y>=top_edge && y<top_edge+57) ||
       ((y>=top_edge && y<top_edge+2 || y>=top_edge+55 && y<top_edge+57) && x>=24 && x<616))color=RED;
    if(editing && x>=448 && x<612 && y>=top_edge+4 && y<top_edge+53)color=RED;
    if(x>=504 && x<600)begin
     if(y>=150 && y<166)begin setting_row=0;number=(volume*100)>>8;text_on=1;row=y-150;end
     if(y>=207 && y<223)begin setting_row=1;number=(brightness*100)>>8;text_on=1;row=y-207;end
     if(y>=265 && y<281)begin setting_row=2;number=interval_seconds;text_on=1;row=y-265;end
     if(y>=322 && y<338)begin setting_row=3;text_on=1;row=y-322;end
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

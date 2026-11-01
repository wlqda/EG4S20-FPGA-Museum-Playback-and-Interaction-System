// Arbitrary initial time, then a real one-second tick; no RTC dependency.
// Display state is published only in vertical blanking; no extra pixel latency.
module baseline_clock #(parameter CLOCK_HZ=25000000, MOVE_FRAMES=3,
 parameter INITIAL_HOUR=13, INITIAL_MINUTE=47, INITIAL_SECOND=26)(
 input clk,rst,input [9:0] x,y,input active,enabled,input [23:0] base_rgb,
 output reg [23:0] out_rgb);
 reg [24:0] ticks;
 reg visible; // Publish SW1 visibility in blanking, without stopping timekeeping.
 reg [3:0] sec_ones,sec_tens,min_ones,min_tens,hour_ones,hour_tens;
 reg [3:0] show_so,show_st,show_mo,show_mt,show_ho,show_ht;
 // Readable numeric probes; these unused expressions disappear in synthesis.
 wire [5:0] seconds=sec_tens*6'd10+sec_ones;
 wire [5:0] minutes=min_tens*6'd10+min_ones;
 wire [4:0] hours=hour_tens*5'd10+hour_ones;
 wire [5:0] show_seconds=show_st*6'd10+show_so;
 wire [4:0] show_hours=show_ht*5'd10+show_ho;
 reg [9:0] pos_x,pos_y;
 reg dir_x,dir_y;
 reg [7:0] frames;
 wire frame_start=x==0 && y==480;
 always @(posedge clk)begin
  if(rst)begin
   ticks<=0;visible<=0;
   sec_ones<=INITIAL_SECOND%10;sec_tens<=INITIAL_SECOND/10;
   min_ones<=INITIAL_MINUTE%10;min_tens<=INITIAL_MINUTE/10;
   hour_ones<=INITIAL_HOUR%10;hour_tens<=INITIAL_HOUR/10;
   show_so<=INITIAL_SECOND%10;show_st<=INITIAL_SECOND/10;
   show_mo<=INITIAL_MINUTE%10;show_mt<=INITIAL_MINUTE/10;
   show_ho<=INITIAL_HOUR%10;show_ht<=INITIAL_HOUR/10;
   pos_x<=173;pos_y<=107;dir_x<=0;dir_y<=0;frames<=0;
  end else begin
   if(ticks==CLOCK_HZ-1)begin
    ticks<=0;
    if(sec_ones==9)begin sec_ones<=0;
     if(sec_tens==5)begin sec_tens<=0;
      if(min_ones==9)begin min_ones<=0;
       if(min_tens==5)begin min_tens<=0;
        if(hour_tens==2 && hour_ones==3)begin hour_tens<=0;hour_ones<=0;end
        else if(hour_ones==9)begin hour_ones<=0;hour_tens<=hour_tens+1'b1;end
        else hour_ones<=hour_ones+1'b1;
       end else min_tens<=min_tens+1'b1;
      end else min_ones<=min_ones+1'b1;
     end else sec_tens<=sec_tens+1'b1;
    end else sec_ones<=sec_ones+1'b1;
   end else ticks<=ticks+1'b1;
   if(frame_start)begin
    visible<=enabled;
    show_so<=sec_ones;show_st<=sec_tens;show_mo<=min_ones;show_mt<=min_tens;show_ho<=hour_ones;show_ht<=hour_tens;
    if(frames==MOVE_FRAMES-1)begin
     frames<=0;
     if(!dir_x)begin if(pos_x==445)begin dir_x<=1;pos_x<=444;end else pos_x<=pos_x+1'b1;end
     else if(pos_x==0)begin dir_x<=0;pos_x<=1;end else pos_x<=pos_x-1'b1;
     if(!dir_y)begin if(pos_y==448)begin dir_y<=1;pos_y<=447;end else pos_y<=pos_y+1'b1;end
     else if(pos_y==0)begin dir_y<=0;pos_y<=1;end else pos_y<=pos_y-1'b1;
    end else frames<=frames+1'b1;
   end
  end
 end
 function [6:0] segments;input [3:0] d;begin
  case(d)
   0:segments=7'b1111110;1:segments=7'b0110000;2:segments=7'b1101101;
   3:segments=7'b1111001;4:segments=7'b0110011;5:segments=7'b1011011;
   6:segments=7'b1011111;7:segments=7'b1110000;8:segments=7'b1111111;
   9:segments=7'b1111011;default:segments=0;
  endcase
 end endfunction
 reg [9:0] dx,dy;reg [3:0] digit;reg [6:0] seg;
 reg [4:0] col;reg [3:0] cell_index;reg ink;
 always @*begin
  out_rgb=base_rgb;dx=x-pos_x;dy=y-pos_y;digit=0;seg=0;col=0;cell_index=0;ink=0;
  if(active && visible && dx>=8 && dx<136 && dy>=4 && dy<28)begin
    cell_index=(dx-8)>>4;col=(dx-8)&15;
    case(cell_index)
     0:digit=show_ht;1:digit=show_ho;
     3:digit=show_mt;4:digit=show_mo;
     6:digit=show_st;7:digit=show_so;
    endcase
    seg=segments(digit);
    if(cell_index==2 || cell_index==5)ink=col>=6 && col<=8 && ((dy>=10 && dy<=12)||(dy>=20 && dy<=22));
    else begin
     if(col>=3 && col<=10)begin
      if(dy>=5 && dy<=7 && seg[6])ink=1;
      if(dy>=14 && dy<=16 && seg[0])ink=1;
      if(dy>=24 && dy<=26 && seg[3])ink=1;
     end
     if(dy>=7 && dy<=14)begin
      if(col>=10 && col<=12 && seg[5])ink=1;
      if(col>=1 && col<=3 && seg[1])ink=1;
     end
     if(dy>=16 && dy<=24)begin
      if(col>=10 && col<=12 && seg[4])ink=1;
      if(col>=1 && col<=3 && seg[2])ink=1;
     end
    end
    if(ink)out_rgb=24'h000000;
  end
 end
endmodule


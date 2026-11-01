// One-cycle overlay replacing the existing gui_rgb_q register (no timing change).
// 192 columns x 8 samples = 32 ms at 48 kHz. Whole snapshots swap in blanking.
module museum_waveform_reference(
 input clk,rst,input [9:0] x,y,input active,
 input [23:0] base_rgb,input enabled,paused,loading,ended,input [7:0] error,
 input sample_valid,input [23:0] sample_data,input clear,
 output reg [23:0] out_rgb);
 (* ram_style="block" *) reg [11:0] trace[0:511];
 reg bank,trace_valid,pending;reg [7:0] column;reg [2:0] n;
 reg signed [5:0] lo,hi;
 wire signed [5:0] sample_value=sample_data[23:18];
 wire signed [5:0] next_lo=(n==0 || sample_value<lo) ? sample_value : lo;
 wire signed [5:0] next_hi=(n==0 || sample_value>hi) ? sample_value : hi;
 wire [9:0] next_x=x+1'b1;
 wire [7:0] fetch_column=next_x>=432 && next_x<624 ? next_x-432 : 0;
 reg [11:0] trace_word;
 always @(posedge clk)trace_word<=trace[{bank,fetch_column}];
 wire signed [7:0] top_offset=8'sd56-$signed(trace_word[11:6]);
 wire signed [7:0] bottom_offset=8'sd56-$signed(trace_word[5:0]);
 wire in_window=x>=432 && x<624 && y>=16 && y<96;
 reg [15:0] glyph;reg [3:0] glyph_row,glyph_col;reg text_on;
 wire [15:0] glyph_bits;
 museum_phase6_font status_font(.glyph(glyph),.row(glyph_row),.bits(glyph_bits));
 function [15:0] status_char;input [3:0] p;begin
  status_char=32;
  if(error!=0)case(p)
   0:status_char=16'h8bf7;1:status_char=16'h68c0;2:status_char=16'h67e5;
   3:status_char=16'h0054;4:status_char=16'h0046;5:status_char=16'h5361;
   7:status_char=error[7:4]<10 ? 48+error[7:4] : 55+error[7:4];
   8:status_char=error[3:0]<10 ? 48+error[3:0] : 55+error[3:0];
  endcase
  else if(loading)case(p)0:status_char=16'h52a0;1:status_char=16'h8f7d;2:status_char=16'h4e2d;endcase
  else if(ended)case(p)0:status_char=16'h5173;1:status_char=16'h95ed;endcase
  else if(paused)case(p)0:status_char=16'h6682;1:status_char=16'h505c;endcase
  else case(p)0:status_char=16'h64ad;1:status_char=16'h653e;endcase
 end endfunction
 reg [23:0] color;
 always @*begin
  color=base_rgb;glyph=32;glyph_row=0;glyph_col=0;text_on=0;
  if(enabled && active)begin
   // Replace old baked-in fake bars and "voice pending" caption, preserving source PNGs.
   if(x>=264 && x<610 && y>=250 && y<354)color=24'hf4eee4;
   if(x>=280 && x<416 && y>=450 && y<472)color=24'hf4eee4;
   if(x>=284 && x<428 && y>=282 && y<298)begin
    text_on=1;glyph=status_char((x-284)>>4);glyph_row=y-282;glyph_col=x-284;
   end
   if(x>=288 && x<368 && y>=454 && y<470)begin
    text_on=1;glyph_row=y-454;glyph_col=x-288;
    case((x-288)>>4)
     0:glyph=16'h64ad;1:glyph=16'h653e;2:glyph=16'h002f;
     3:glyph=16'h6682;4:glyph=16'h505c;
    endcase
   end
   if(text_on && glyph_bits[15-glyph_col])color=24'h534b40;
  end

  if(enabled && active && in_window)begin
   color=24'h172329;
   if(x==432 || x==623 || y==16 || y==95)color=error!=0 ? 24'hdd5544 : 24'h728d91;
   else if(y==56)color=24'h34484e;
   if(trace_valid && y>=24 && y<=88 &&
      $signed({1'b0,y})>=top_offset && $signed({1'b0,y})<=bottom_offset)color=24'h63dbc0;
   // Small status icon: amber loading, red fault, grey EOF, pause bars or play.
   if(x>=438 && x<447 && y>=19 && y<24)begin
    if(error!=0)color=24'hff6655;
    else if(loading)color=24'hffca62;
    else if(ended)color=24'h819094;
    else if(!paused || x<441 || x>=444)color=24'h63dbc0;
   end
  end
 end
 always @(posedge clk)begin
  if(rst)out_rgb<=0;else out_rgb<=color;
  if(rst || clear || !enabled)begin
   bank<=0;trace_valid<=0;pending<=0;column<=0;n<=0;lo<=0;hi<=0;
  end else if(pending)begin
   if(x==0 && y==480)begin bank<=~bank;trace_valid<=1;pending<=0;column<=0;end
  end else if(sample_valid && !paused && !loading && !ended && error==0)begin
   lo<=next_lo;hi<=next_hi;n<=n+1'b1;
   if(n==7)begin
    trace[{!bank,column}]<={next_hi,next_lo};
    if(column==191)pending<=1;else column<=column+1'b1;
   end
  end
 end
endmodule

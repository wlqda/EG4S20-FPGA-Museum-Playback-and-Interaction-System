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
 wire [7:0] fetch_column=next_x>=336 && next_x<528 ? next_x-336 : 0;
 reg [11:0] trace_word;
 always @(posedge clk)trace_word<=trace[{bank,fetch_column}];
 wire signed [9:0] top_offset=10'sd316-$signed(trace_word[11:6]);
 wire signed [9:0] bottom_offset=10'sd316-$signed(trace_word[5:0]);
 wire in_window=x>=336 && x<528 && y>=276 && y<352;
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
   // V2 guide BMPs carry clean paper; text and trace overlay it directly.
   if(x>=284 && x<428 && y>=354 && y<370)begin
    text_on=1;glyph=status_char((x-284)>>4);glyph_row=y-354;glyph_col=x-284;
   end
   if(text_on && glyph_bits[15-glyph_col])color=24'h534b40;
  end

  if(enabled && active && in_window)begin
   color=base_rgb;
   if(trace_valid && y>=284 && y<=348 &&
      $signed({1'b0,y})>=top_offset && $signed({1'b0,y})<=bottom_offset)color=24'ha63826;

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

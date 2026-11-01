// One register stage; exactly 640 beats per line, TLAST on beat 640.
module video_axis #(parameter WIDTH=640)(input clk,rst,de,vs,input [23:0] rgb,
 output reg valid,user,last,output reg [23:0] data);
 reg previous_de,previous_vs,sof_armed;
 reg [10:0] x;
 always @(posedge clk) begin
  if(rst) begin previous_de<=0;previous_vs<=1;sof_armed<=1;x<=0;valid<=0;user<=0;last<=0;data<=0;end
  else begin
   previous_de<=de;previous_vs<=vs;valid<=de;user<=0;last<=0;data<=rgb;
   if(previous_vs && !vs) sof_armed<=1;
   if(de) begin
    if(!previous_de) begin x<=1;user<=sof_armed;sof_armed<=0;last<=WIDTH==1;end
    else begin x<=x+1'b1;last<=x==WIDTH-1;end
   end else x<=0;
  end
 end
endmodule

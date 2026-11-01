// Hold KEY2+KEY3 for one second to enter/leave camera maintenance. Gate both
// consumers immediately on a chord, and keep them gated until release settles.
module museum_camera_keys #(parameter HOLD_CYCLES=25000000, RELEASE_CYCLES=500000)(
 input clk,rst,input [2:0] keys_n,output reg maintenance,
 output [2:0] museum_keys_n,camera_keys_n,output blocked);
 (* async_reg="true" *) reg [2:0] sync1,sync2;
 localparam HW=$clog2(HOLD_CYCLES+1),RW=$clog2(RELEASE_CYCLES+1);
 reg [HW-1:0] hold_count;reg [RW-1:0] release_count;
 reg chord_latched,toggled;
 wire chord=!sync2[0] && !sync2[1];
 assign blocked=chord || chord_latched;
 assign museum_keys_n=maintenance || blocked ? 3'b111 : sync2;
 assign camera_keys_n=!maintenance || blocked ? 3'b111 : sync2;
 always @(posedge clk)begin
  if(rst)begin sync1<=7;sync2<=7;maintenance<=0;hold_count<=0;release_count<=0;chord_latched<=0;toggled<=0;end
  else begin
   sync1<=keys_n;sync2<=sync1;
   if(chord)begin
    chord_latched<=1;release_count<=0;
    if(!toggled)begin
     if(hold_count==HOLD_CYCLES-1)begin maintenance<=!maintenance;toggled<=1;end
     else hold_count<=hold_count+1'b1;
    end
   end else begin
    hold_count<=0;
    if(sync2==7 && chord_latched)begin
     if(release_count==RELEASE_CYCLES-1)begin chord_latched<=0;toggled<=0;release_count<=0;end
     else release_count<=release_count+1'b1;
    end else release_count<=0;
   end
  end
 end
endmodule

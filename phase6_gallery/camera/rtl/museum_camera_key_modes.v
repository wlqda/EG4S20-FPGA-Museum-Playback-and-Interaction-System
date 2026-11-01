// SW3 owns key routing. Camera mode follows the uploaded KEY2/3/4 controls.
// Before returning to the museum, require all keys released for 20 ms, so a
// camera key held across a mode change cannot become a menu release event.
module museum_camera_key_modes #(parameter RELEASE_CYCLES=500000)(
 input clk,rst,gesture_enabled,input [2:0] keys_n,
 output [2:0] museum_keys_n,camera_keys_n,output menu_blocked);
 (* async_reg="true" *) reg [2:0] sync1,sync2;
 localparam RW=$clog2(RELEASE_CYCLES+1);
 reg [RW-1:0] release_count;reg menu_ready;
 assign menu_blocked=gesture_enabled || !menu_ready;
 assign museum_keys_n=menu_blocked ? 3'b111 : sync2;
 assign camera_keys_n=gesture_enabled ? sync2 : 3'b111;
 always @(posedge clk)begin
  if(rst)begin sync1<=7;sync2<=7;release_count<=0;menu_ready<=0;end
  else begin
   sync1<=keys_n;sync2<=sync1;
   if(gesture_enabled)begin release_count<=0;menu_ready<=0;end
   else if(!menu_ready)begin
    if(sync2!=7)release_count<=0;
    else if(release_count==RELEASE_CYCLES-1)begin menu_ready<=1;release_count<=0;end
    else release_count<=release_count+1'b1;
   end
  end
 end
endmodule

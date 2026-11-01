// Phase 1 controls the verified fixed AV stream. Unsupported image requests
// report E1; no TF image or slideshow completion is fabricated.
module museum_phase1_control(input clk,rst,input cmd_valid,
 input [7:0] cmd_opcode,input [31:0] cmd_arg,
 output reg playing,paused,output reg [8:0] volume,brightness,
 output reg [7:0] command_error);
 always @(posedge clk) begin
  if(rst) begin playing<=0;paused<=0;volume<=256;brightness<=256;command_error<=0;end
  else if(cmd_valid) begin
   command_error<=0;
   case(cmd_opcode)
    8'h02,8'h03:begin playing<=1;paused<=0;end
    8'h04:paused<=cmd_arg[0];
    8'h05:begin playing<=0;paused<=0;end
    8'h06:volume<=cmd_arg[8:0]>256 ? 9'd256 : cmd_arg[8:0];
    8'h07:brightness<=cmd_arg[8:0]>256 ? 9'd256 : cmd_arg[8:0];
    default:command_error<=8'he1;
   endcase
  end
 end
endmodule

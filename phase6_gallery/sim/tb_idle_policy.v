`timescale 1ns/1ps
module tb_idle_policy;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,frame=0,gesture=0;reg [7:0] events=0;
 wire [3:0] page;wire [4:0] screen;reg passed=0;
 museum_phase6_ui #(.CLK_HZ(10)) dut(.clk(clk),.rst(rst),.frame_start(frame),
  .carousel_enabled(1'b0),.gesture_enabled(gesture),.events(events),
  .image_mode(1'b1),.media_playing(1'b0),.media_paused(1'b0),.media_busy(1'b0),.audio_busy(1'b0),
  .resource_count(16'd29),.shown_index({11'd0,screen}),.shown_valid(1'b1),
  .media_error(8'd0),.volume(9'd256),.brightness(9'd256),
  .page(page),.focus(),.exhibit(),.editing(),.autoplay(),.interval_seconds(),.welcome(),
  .screen_index(screen),.photo_index(),.zoom(),.fade_level(),
  .cmd_valid(),.cmd_ready(1'b1),.cmd_opcode(),.cmd_arg(),.nav_ready());
 task cycles;input integer n;begin repeat(n)@(negedge clk);end endtask
 task enter_home;begin
  events=8'h08;cycles(1);events=0;frame=1;cycles(2);frame=0;
  if(page!==0)$fatal(1,"home entry");
 end endtask
 initial begin
  cycles(3);rst=0;enter_home;
  cycles(200);if(dut.idle_return || page!==0)$fatal(1,"returned at old 20s limit");
  cycles(197);if(dut.idle_return)$fatal(1,"expired before 40s");
  cycles(1);if(!dut.idle_return)$fatal(1,"40s deadline missing");
  frame=1;cycles(2);frame=0;if(page!==7)$fatal(1,"40s return did not commit");
  enter_home;gesture=1;cycles(1000);frame=1;cycles(3);frame=0;
  if(page!==0 || dut.idle_return || dut.idle_seconds!=0)$fatal(1,"gesture mode timed out");
  gesture=0;cycles(1);cycles(399);
  if(dut.idle_return || page!==0)$fatal(1,"gesture-off reused prior timeout");
  cycles(1);if(!dut.idle_return)$fatal(1,"fresh 40s interval missing");
  // Switch on while an expiry is pending, exactly when blanking arrives.
  gesture=1;frame=1;cycles(3);frame=0;
  if(page!==0 || dut.idle_return)$fatal(1,"pending return escaped gesture enable");
  gesture=0;cycles(1);cycles(300);events=1;cycles(1);events=0;
  cycles(399);if(dut.idle_return)$fatal(1,"interaction did not restart timeout");
  cycles(1);if(!dut.idle_return)$fatal(1,"interaction timeout missing");
  passed=1;$display("PASS idle policy: default 40s, gesture hold, fresh 40s after disable, pending expiry cancellation, activity reset");$finish;
 end
 initial begin #1000000;$fatal(1,"idle policy watchdog");end
endmodule

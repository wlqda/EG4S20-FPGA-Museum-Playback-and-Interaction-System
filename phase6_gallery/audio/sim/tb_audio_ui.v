`timescale 1ns/1ps
module tb_audio_ui;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [3:0] raster=0;always @(posedge clk)raster<=raster+1'b1;
 wire frame_start=raster==15;
 reg [7:0] events=0;reg [15:0] shown=0;reg shown_valid=0;
 reg playing=0,paused=0,busy=0,gate=1;reg [7:0] error=0;
 wire [3:0] page,photo;wire [4:0] screen,fade;wire [1:0] focus,exhibit,zoom;
 wire editing,autoplay,welcome,valid;wire [5:0] interval_s;wire [7:0] opcode;wire [31:0] arg;
 reg passed=0;integer starts=0,stops=0,last_id=-1,delay_count=0;reg [15:0] target;
 wire ready=gate && !busy;
 museum_phase6_ui #(.CLK_HZ(100)) dut(.clk(clk),.rst(rst),.frame_start(frame_start),.gesture_enabled(1'b0),.carousel_enabled(1'b1),
  .events(events),.image_mode(1'b1),.media_playing(playing),.media_paused(paused),.media_busy(busy),.audio_busy(1'b0),
  .resource_count(16'd29),.shown_index(shown),.shown_valid(shown_valid),.media_error(error),
  .volume(9'd256),.brightness(9'd256),.page(page),.focus(focus),.exhibit(exhibit),.editing(editing),
  .autoplay(autoplay),.interval_seconds(interval_s),.welcome(welcome),.screen_index(screen),
  .photo_index(photo),.zoom(zoom),.fade_level(fade),.cmd_valid(valid),.cmd_ready(ready),.cmd_opcode(opcode),.cmd_arg(arg),.nav_ready());
 always @(posedge clk)if(!rst)begin
  if(delay_count>0)begin delay_count<=delay_count-1;if(delay_count==1)begin busy<=0;shown<=target;shown_valid<=1;end end
  if(valid && ready)case(opcode)
   1:begin busy<=1;delay_count<=5;target<=arg;playing<=0;paused<=0;end
   3:begin starts<=starts+1;last_id<=arg;playing<=1;paused<=0;end
   4:paused<=arg[0];
   5:begin stops<=stops+1;playing<=0;paused<=0;end
   default:$fatal(1,"unexpected command %d",opcode);
  endcase
 end
 task cycles;input integer n;begin repeat(n)@(negedge clk);end endtask
 task key;input [7:0] e;begin events=e;cycles(1);events=0;cycles(40);end endtask
 integer before_starts;reg [39:0] held;
 initial begin
  cycles(3);rst=0;cycles(40);key(8);key(4);key(4);key(4);cycles(80);
  if(page!=4 || starts!=1 || last_id!=0)$fatal(1,"audio entry did not start ID0");
  cycles(2500);if(page!=4 || starts!=1)$fatal(1,"idle interrupted narration");
  key(4);if(!paused)$fatal(1,"pause missing");cycles(2200);if(page!=4)$fatal(1,"pause idle");
  key(4);if(paused)$fatal(1,"resume missing");
  key(1);cycles(80);if(last_id!=1 || starts!=2 || stops!=1)$fatal(1,"track switch lifecycle");
  playing=0;cycles(100);if(starts!=2)$fatal(1,"automatic EOF replay");
  key(4);cycles(40);if(starts!=3)$fatal(1,"explicit replay missing");
  gate=0;key(1);wait(valid);held={opcode,arg};cycles(40);
  if(!valid || {opcode,arg}!==held)$fatal(1,"backpressure payload changed");
  gate=1;cycles(100);if(last_id!=2)$fatal(1,"backpressure recovery");
  key(8);cycles(100);if(page!=1 || playing)$fatal(1,"return did not stop");
  passed=1;$display("PASS audio UI: entry, >20sec, pause/resume, track switch, EOF/replay, backpressure, exit");$finish;
 end
 initial begin #2000000;$fatal(1,"watchdog");end
endmodule

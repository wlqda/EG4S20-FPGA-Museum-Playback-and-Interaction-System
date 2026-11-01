`timescale 1ns/1ps
module tb_gallery_ui;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [3:0] raster=0;wire frame_start=raster==15;
 always @(posedge clk)raster<=raster+1'b1;
 reg [7:0] events=0;reg image_mode=1,shown_valid=0,busy=0;reg carousel_enabled=1;
 reg [15:0] shown_index=0;reg [7:0] media_error=0;
 wire [3:0] page,photo_index;wire [4:0] screen_index,fade;
 wire [1:0] focus,exhibit,zoom;wire editing,autoplay,welcome;
 wire [5:0] interval_seconds;wire cmd_valid;wire [7:0] cmd_opcode;wire [31:0] cmd_arg;
 reg [4:0] target;reg [4:0] delay_count=0;integer selects=0;reg passed=0;
 museum_phase6_ui #(.CLK_HZ(100),.IDLE_SECONDS(40),.ZOOM_IDLE_SECONDS(5)) dut(
  .clk(clk),.rst(rst),.frame_start(frame_start),.gesture_enabled(1'b0),.carousel_enabled(carousel_enabled),.events(events),
  .image_mode(image_mode),.media_playing(1'b0),.media_paused(1'b0),.media_busy(busy),.audio_busy(1'b0),
  .resource_count(16'd29),.shown_index(shown_index),.shown_valid(shown_valid),
  .media_error(media_error),.volume(9'd256),.brightness(9'd256),
  .page(page),.focus(focus),.exhibit(exhibit),.editing(editing),.autoplay(autoplay),
  .interval_seconds(interval_seconds),.welcome(welcome),.screen_index(screen_index),
  .photo_index(photo_index),.zoom(zoom),.fade_level(fade),
  .cmd_valid(cmd_valid),.cmd_ready(!busy),.cmd_opcode(cmd_opcode),.cmd_arg(cmd_arg),.nav_ready());
 always @(posedge clk)if(!rst)begin
  if(delay_count!=0)begin
   delay_count<=delay_count-1'b1;
   if(delay_count==1)begin busy<=0;shown_index<=target;shown_valid<=1;end
  end
  if(cmd_valid && !busy)begin
   if(cmd_opcode!=1)$fatal(1,"Unexpected opcode %d",cmd_opcode);
   target<=cmd_arg[4:0];busy<=1;delay_count<=5;selects<=selects+1;
  end
 end
 task cycles;input integer count;begin repeat(count)@(negedge clk);end endtask
 task key;input [7:0] event_code;begin events=event_code;cycles(1);events=0;cycles(2);end endtask
 task check;input ok;input [255:0] message;begin if(!ok)$fatal(1,"%s",message);end endtask
 initial begin
  cycles(3);rst=0;cycles(40);
  check(page==7 && screen_index==16 && shown_index==16,"boot first photo");
  key(1);cycles(600);
  check(screen_index==17 && shown_index==17 && fade==16,"manual next fades and loads");
  key(4);cycles(18);check(zoom==1,"confirm enters 2x zoom");
  key(1);cycles(18);check(zoom==2,"next raises zoom to 4x");
  key(2);cycles(18);check(zoom==1,"previous lowers zoom to 2x");
  key(4);cycles(18);check(zoom==0,"confirm exits zoom");
  key(4);cycles(510);check(zoom==0 && screen_index==17,"zoom idle exits without changing photo");
  cycles(840);cycles(600);
  check(screen_index==18 && shown_index==18,"autoplay resumes after zoom idle");
  carousel_enabled=0;cycles(1600);
  check(screen_index==18 && shown_index==18,"SW4 off holds current photo");
  key(1);cycles(600);check(screen_index==19 && shown_index==19,"manual next while SW4 off");
  carousel_enabled=1;cycles(700);check(screen_index==19,"SW4 on restarts full interval");
  cycles(800);check(screen_index==20 && shown_index==20,"SW4 on resumes carousel");
  key(8);cycles(35);check(page==0 && zoom==0,"long confirm enters home");
  key(1);key(1);cycles(20);check(focus==2,"three-entry home third item");
  key(1);cycles(20);check(focus==0,"home forward wraps at three");
  key(2);cycles(20);check(focus==2,"home backwards wraps at three");
  key(4);cycles(40);check(page==5,"third home item opens settings");
  key(8);cycles(40);check(page==0,"settings returns home");
  carousel_enabled=0;cycles(2000);
  check(page==0,"no return at old 20-second limit");cycles(2100);
  check(page==7,"SW4 off preserves 40-second idle return");
  passed=1;$display("PASS gallery UI: photo selection, fades, zoom levels, idle return, autoplay, home; selects=%0d",selects);$finish;
 end
 initial begin #3000000;$fatal(1,"watchdog");end
endmodule

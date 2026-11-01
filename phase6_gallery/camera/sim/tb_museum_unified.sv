`timescale 1ns/1ps
module tb_museum_unified;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,maintenance=0;reg [2:0] pins=7;wire blocked;wire [2:0] keys_n,cam_keys;
 museum_camera_key_modes #(.RELEASE_CYCLES(4)) mode(.clk(clk),.rst(rst),.gesture_enabled(maintenance),.keys_n(pins),
 .museum_keys_n(keys_n),.camera_keys_n(cam_keys),.menu_blocked(blocked));
 wire [7:0] keys;
 museum_keys #(.DEBOUNCE_CYCLES(2),.LONG_PRESS_CYCLES(30)) physical(.pixel_clk(clk),.pixel_rst(rst || blocked || maintenance),.keys_n(keys_n),.events(keys));
 reg [4:0] phase=0;always @(posedge clk)if(rst)phase<=0;else phase<=phase==19 ? 0 : phase+1;
 wire frame_start=phase==0;
 reg valid=0;reg [2:0] raw_direction=0;
 wire [2:0] direction=raw_direction==2 ? 3 : raw_direction==3 ? 2 : raw_direction;
 wire [7:0] nav;wire overflow,ready;
 camera_nav_adapter #(.WAIT_CYCLES(100)) adapter(.clk(clk),.rst(rst),.enabled(!maintenance && !blocked),
 .frame_start(frame_start),.ready(ready),.event_valid(valid),.direction(direction),.events(nav),.overflow(overflow));
 wire [3:0] page,photo;wire [1:0] focus,exhibit,zoom;wire [4:0] screen,fade;
 wire editing,autoplay,welcome,cmd_valid;wire [5:0] interval;wire [7:0] opcode;wire [31:0] arg;
 reg shown=1,busy=0;wire [7:0] routed=page==7 && nav[2] ? 8'h08 : nav;
 museum_phase6_ui #(.CLK_HZ(100000)) ui(.clk(clk),.rst(rst),.frame_start(frame_start),.gesture_enabled(1'b0),.carousel_enabled(1'b0),
 .events(keys!=0 ? keys : routed),.image_mode(1'b1),.media_playing(1'b1),.media_paused(1'b0),.media_busy(busy),.audio_busy(1'b0),
 .resource_count(16'd29),.shown_index({11'd0,screen}),.shown_valid(shown),.media_error(8'd0),.volume(9'd256),.brightness(9'd256),
 .page(page),.focus(focus),.exhibit(exhibit),.editing(editing),.autoplay(autoplay),.interval_seconds(interval),.welcome(welcome),
 .screen_index(screen),.photo_index(photo),.zoom(zoom),.fade_level(fade),.cmd_valid(cmd_valid),.cmd_ready(1'b1),.cmd_opcode(opcode),.cmd_arg(arg),.nav_ready(ready));
 integer key_count=0;always @(posedge clk)if(keys!=0)key_count=key_count+1;
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task gesture(input [2:0] d);integer k;begin
  k=0;while(!ready && k<200)begin cycles(1);k=k+1;end
  if(!ready)$fatal(1,"navigation never ready");raw_direction=d;valid=1;cycles(1);valid=0;cycles(65);
 end endtask
 task check(input [3:0] p,input [1:0] f);begin if(page!==p || focus!==f)$fatal(1,"page/focus %0d/%0d expected %0d/%0d",page,focus,p,f);end endtask
 reg passed=0;integer saved;
 initial begin
  cycles(6);rst=0;cycles(60);check(7,0);
  // Attract -> home -> list -> next -> detail -> guide -> back, mirrored X.
  gesture(5);check(0,0);if(zoom!=0)$fatal(1,"gesture zoomed attract page");
  gesture(5);check(1,0);gesture(2);check(1,1);gesture(5);check(2,1);
  if(exhibit!=1)$fatal(1,"wrong exhibit");gesture(5);check(4,1);gesture(4);check(1,1);
  // Loading blocks delivery; one queued gesture is delivered exactly once.
  busy=1;cycles(3);if(ready)$fatal(1,"ready during load");raw_direction=3;valid=1;cycles(1);valid=0;
  cycles(30);check(1,1);busy=0;cycles(50);check(1,0);
  // SW3 camera mode must isolate camera keys, including release across modes.
  saved=key_count;maintenance=1;cycles(20);if(keys_n!=7)$fatal(1,"camera mode entry");
  pins=7;cycles(20);if(key_count!=saved)$fatal(1,"mode leaked key event");
  pins=6;cycles(8);if(cam_keys!=6 || keys_n!=7)$fatal(1,"camera key routing");pins=7;cycles(10);
  pins=3;cycles(10);maintenance=0;cycles(20);if(!blocked)$fatal(1,"held-key guard missing");pins=7;cycles(20);
  if(key_count!=saved)$fatal(1,"maintenance keys leaked");
  // Original physical KEY2 still selects next after leaving maintenance.
  pins=6;cycles(15);pins=7;cycles(60);check(1,1);
  if(overflow)$fatal(1,"unexpected queue overflow");
  passed=1;$display("PASS unified UI: mirrored navigation, guide, loading queue, SW3 key isolation/release and physical keys");$finish;
 end
 initial begin #100000;$fatal(1,"watchdog");end
endmodule

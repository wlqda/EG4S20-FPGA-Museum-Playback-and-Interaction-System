`timescale 1ns/1ps
module tb_camera_swipe_tracker;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,enabled=1,restart=0,epoch_reset=0,sample_valid=0,candidate_valid=1,clipped=0;
 reg [3:0] edges=0;reg [31:0] frame_id=0;reg [9:0] cx=320,cy=240,width=96,height=128;
 wire [2:0] state,reason,direction,event_direction;wire armed,event_valid,target_visible;
 wire [31:0] event_sequence;wire [9:0] origin_x,origin_y;
 reg passed=0;integer n=0;
 wire [7:0] events;wire overflow;reg [4:0] raster=0;
 always @(posedge clk)raster<=raster+1'b1;
 wire frame_start=raster==31;wire nav_ready;
 camera_swipe_tracker #(.STALE_CYCLES(400),.TRACK_CYCLES(500),.ARM_CYCLES(800)) dut(.*);
 wire mirrored_valid;wire [2:0] mirrored_direction;
 camera_swipe_tracker #(.STALE_CYCLES(400),.TRACK_CYCLES(500),.ARM_CYCLES(800),.MIRROR_X(1)) mirror_dut(
  .event_valid(mirrored_valid),.event_direction(mirrored_direction),.state(),.reason(),.direction(),
  .armed(),.event_sequence(),.origin_x(),.origin_y(),.target_visible(),.*);
 always @(negedge clk)if(!rst && event_valid)begin
  if(!mirrored_valid || mirrored_direction!=(event_direction==2 ? 3 : event_direction==3 ? 2 : event_direction))
   $fatal(1,"Mirror maps horizontal events only");
 end
 camera_nav_adapter adapter(.clk(clk),.rst(rst),.enabled(enabled),.frame_start(frame_start),
  .ready(nav_ready),.event_valid(event_valid),.direction(event_direction),.events(events),.overflow(overflow));
 wire [7:0] mirror_events;wire mirror_overflow;
 wire [2:0] user_direction=event_direction==2 ? 3 : event_direction==3 ? 2 : event_direction;
 camera_nav_adapter mirror_adapter(.clk(clk),.rst(rst),.enabled(enabled),.frame_start(frame_start),
  .ready(nav_ready),.event_valid(event_valid),.direction(user_direction),.events(mirror_events),.overflow(mirror_overflow));
 always @(negedge clk)if(!rst)begin
  if(mirror_overflow!==overflow)$fatal(1,"Mirror changed queue behavior");
  if(mirror_events!=={events[7:2],events[0],events[1]})$fatal(1,"Mirror navigation must swap previous/next only");
 end
 wire [3:0] page;wire [1:0] focus;
 wire cmd_valid;wire [7:0] cmd_opcode;wire [31:0] cmd_arg;
 reg [15:0] shown_index=0;reg shown_valid=0;
 always @(posedge clk)if(cmd_valid && cmd_opcode==1)begin shown_index<=cmd_arg[15:0];shown_valid<=1;end
 museum_phase6_ui #(.CLK_HZ(100000),.GESTURE_MODE(1)) ui(.clk(clk),.rst(rst),.frame_start(frame_start),.events(events),
  .image_mode(1'b1),.media_playing(1'b0),.media_paused(1'b0),.media_busy(1'b0),
  .resource_count(16'd29),.shown_index(shown_index),.shown_valid(shown_valid),.media_error(8'd0),
  .volume(9'd256),.brightness(9'd256),.page(page),.focus(focus),.exhibit(),.editing(),
  .autoplay(),.interval_seconds(),.welcome(),.screen_index(),.photo_index(),.zoom(),.fade_level(),
  .cmd_valid(cmd_valid),.cmd_ready(1'b1),.cmd_opcode(cmd_opcode),.cmd_arg(cmd_arg),.nav_ready(nav_ready));
 always @(posedge clk)if(event_valid)n=n+1;
 task cycles(input integer k);repeat(k)@(negedge clk);endtask
 task check(input bit ok,input string msg);if(!ok)$fatal(1,"%s state=%d reason=%d events=%d",msg,state,reason,n);endtask
 task point(input integer xx,yy);begin
  cx=xx;cy=yy;frame_id=frame_id+1;sample_valid=1;cycles(1);sample_valid=0;cycles(3);
 end endtask
 task center;begin repeat(6)point(320,240);check(armed,"center arms");end endtask
 task swipe(input integer dx,dy);begin
  center();point(320+dx*24,240+dy*24);point(320+dx*40,240+dy*40);
  point(320+dx*56,240+dy*56);point(320+dx*56,240+dy*56);point(320+dx*56,240+dy*56);cycles(100);
 end endtask
 initial begin
  cycles(3);rst=0;cycles(100);
  swipe(0,-1);check(n==1 && event_sequence==1 && page==0,"trajectory UP actually returns home");
  // Returning through the opposite direction must not create a second event.
  point(320,184);point(320,240);check(n==1 && !armed,"return needs three stable points");
  repeat(4)point(320,240);check(armed,"return rearmed");
  point(320,264);point(320,280);point(320,296);point(320,296);point(320,296);cycles(100);
  check(n==2 && page==1,"trajectory DOWN enters list");
  swipe(1,0);check(n==3 && focus==1,"RIGHT next actual item");
  swipe(-1,0);check(n==4 && focus==0,"LEFT previous actual item");
  // Holding, small tremor, diagonal motion and one large jump do not vote.
  center();repeat(5)begin point(328,240);point(312,240);end
  check(n==4,"tremor suppressed");
  point(350,270);point(375,295);point(400,320);point(400,320);point(400,320);check(n==4,"diagonal suppressed");
  restart=1;cycles(1);restart=0;center();point(480,240);check(n==4 && state==4,"identity jump cancels");
  center();point(344,240);candidate_valid=0;point(360,240);candidate_valid=1;
  point(380,240);point(400,240);check(n==4,"loss cannot bridge motion");
  center();point(344,240);clipped=1;point(360,240);clipped=0;
  point(384,240);check(n==4,"clipping cancels");
  center();point(344,240);point(360,240);point(320,240);point(384,240);check(n==4,"reversal cancels");
  center();sample_valid=1;cx=400;repeat(5)cycles(1);sample_valid=0;
  check(n==4 && state==2,"duplicate frame IDs do not move track");
  frame_id=frame_id-1;sample_valid=1;cycles(1);sample_valid=0;check(state==2,"older IDs ignored");frame_id=frame_id+1;
  point(344,240);cycles(401);point(376,240);point(392,240);check(n==4 && !armed,"stale source cancels");
  center();point(344,240);width=240;point(360,240);width=96;check(n==4 && state==4,"scale jump cancels");
  center();enabled=0;point(344,240);point(360,240);point(376,240);enabled=1;check(n==4,"view disable suppresses");
  center();point(344,240);
  repeat(6)begin cycles(90);point(344,240);end
  point(360,240);point(376,240);check(n==4 && !armed,"trajectory timeout with fresh frames");
  center();repeat(9)begin cycles(90);point(320,240);end
  check(n==4 && armed,"fresh stationary hand remains armed");
  epoch_reset=1;cycles(1);epoch_reset=0;frame_id=0;
  swipe(1,0);check(n==5 && event_sequence==5,"new source epoch re-arms immediately and preserves event count");
  center();point(344,240);point(352,256);point(344,288);point(336,312);
  check(n==5,"no premature horizontal event");point(336,312);point(336,312);
  check(n==6 && event_direction==5,"endpoint corrects initial horizontal motion to DOWN");
  center();point(344,240);point(376,240);check(n==6,"fast swipe awaits endpoint");
  point(376,240);point(376,240);check(n==7,"two motion points and endpoint accepted");
  clipped=1;edges=8;center();point(344,240);point(376,240);point(376,240);point(376,240);
  check(n==8,"learned persistent wrist edge allowed");
  center();point(344,240);edges=10;point(376,240);point(376,240);point(376,240);
  check(n==8 && reason==2,"new edge still rejects");clipped=0;edges=0;
  // Reset ID provenance for a deliberate wrap test; wrap is newer, not stale.
  rst=1;cycles(2);rst=0;frame_id=32'hfffffffb;center();
  point(344,240);point(360,240);point(376,240);point(376,240);point(376,240);check(n==9 && event_sequence==1,"frame ID wrap accepted");
  check(!overflow,"no navigation overflow");
  // Slow and fast passes through the acquisition zone must never re-arm.
  restart=1;cycles(1);restart=0;
  for(integer xx=260;xx<=380;xx=xx+4)begin point(xx,240);check(!armed,"slow return must stop before arming");end
  for(integer xx=380;xx>=260;xx=xx-24)begin point(xx,240);check(!armed,"fast return must stop before arming");end
  point(320,240);repeat(4)point(324,240);check(armed && origin_x==324,"origin committed at end of stabilization");
  point(348,240);point(380,240);point(380,240);point(380,240);check(event_sequence==2,"new action after stable return succeeds");
  passed=1;$display("PASS swipe tracker: four real page mappings, tremor, return, loss, clipping, diagonal, identity, scale, stale, IDs, disable");$finish;
 end
 initial begin #2000000;$fatal(1,"watchdog");end
endmodule

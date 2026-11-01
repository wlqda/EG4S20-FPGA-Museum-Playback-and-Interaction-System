`timescale 1ns/1ps
// Test the actual top-level wiring with boundary mocks for camera/HDMI/SD.
// The real recognizer and uploaded overlay are covered by separate suites.
module tb_full_switches;
 reg clk=0;always #5 clk=~clk;
 reg reset_n=0,sw1=0,sw2=0,sw3=0,sw4=0;reg [2:0] pins=7;tri sd_cmd,scl,sda,ddc;
 wire [3:0] led;wire sdclk,hclk,h0,h1,h2,hscl,pwdn,crst,tx;
 museum_phase6_unified_top dut(.sys_clk(clk),.sys_rst_n(reset_n),.KEY2_N(pins[0]),.KEY3_N(pins[1]),.KEY4_N(pins[2]),
 .SW1(sw1),.SW2(sw2),.SW3(sw3),.SW4(sw4),.SD_CLK(sdclk),.SD_CMD(sd_cmd),.SD_DAT(4'b1111),
 .HDMI_CLK_P(hclk),.HDMI_D0_P(h0),.HDMI_D1_P(h1),.HDMI_D2_P(h2),.HDMI_DDC_SCL(hscl),.HDMI_DDC_SDA(ddc),
 .CAM_PCLK(clk),.CAM_VSYNC(1'b0),.CAM_HREF(1'b0),.CAM_D(8'd0),.CAM_SCL(scl),.CAM_SDA(sda),
 .CAM_PWDN(pwdn),.CAM_RESET_N(crst),.UART_TX(tx),.LED(led));
 defparam dut.clock_switch.STABLE_CYCLES=4;
 defparam dut.gesture_switch.STABLE_CYCLES=4;
 defparam dut.preview_switch.STABLE_CYCLES=4;
 defparam dut.key_modes.RELEASE_CYCLES=4;
 reg frame=0,valid=0;wire [7:0] queued;wire overflow;
 camera_nav_adapter #(.WAIT_CYCLES(100)) real_queue(.clk(clk),.rst(!reset_n),.enabled(dut.gesture_enabled),
 .frame_start(frame),.ready(1'b1),.event_valid(valid),.direction(3'd3),.events(queued),.overflow(overflow));
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task check(input g,p);begin
  if(dut.engine.gesture_enabled!==g || dut.engine.preview_enabled!==p)$fatal(1,"wrong independent switch mapping");
 end endtask
 reg passed=0;
 initial begin
  cycles(5);reset_n=1;cycles(10);check(0,0);
  dut.engine.nav_events=8'h04;cycles(1);if(dut.gallery.gesture_events!=0)$fatal(1,"event escaped disabled SW3");
  sw2=1;cycles(8);check(0,1);
  sw3=1;cycles(8);check(1,1);if(dut.gallery.gesture_events!=8'h08)$fatal(1,"attract gesture did not leave attract page");
  dut.gallery.test_page=1;cycles(1);if(dut.gallery.gesture_events!=4)$fatal(1,"normal enter remapped");
  sw2=0;cycles(8);check(1,0);if(dut.gallery.gesture_events!=4)$fatal(1,"SW2 stopped recognition");
  sw4=1;cycles(1);if(dut.gallery.SW4!==1)$fatal(1,"SW4 no longer controls gallery");check(1,0);
  // A queued event must be discarded on disable, never replayed after enable.
  valid=1;cycles(1);valid=0;cycles(2);if(!real_queue.pending)$fatal(1,"queue fixture did not queue");
  sw3=0;cycles(8);check(0,0);if(real_queue.pending || dut.gallery.gesture_events!=0)$fatal(1,"SW3 failed to clear/block event");
  sw3=1;cycles(8);frame=1;cycles(2);frame=0;if(queued!=0)$fatal(1,"stale event replayed after enable");
  pins=6;cycles(8);
  if(dut.engine.KEY2_N!==0 || dut.gallery.KEY2_N!==1)$fatal(1,"SW3-on KEY2 not assigned to camera");
  pins=5;cycles(8);if(dut.engine.KEY3_N!==0 || dut.gallery.KEY3_N!==1)$fatal(1,"SW3-on KEY3 routing");
  pins=3;cycles(8);if(dut.engine.KEY4_N!==0 || dut.gallery.KEY4_N!==1)$fatal(1,"SW3-on KEY4 routing");
  sw3=0;cycles(8);if(!dut.blocked || dut.gallery.KEY4_N!==1)$fatal(1,"held camera key leaked into menu");
  pins=7;cycles(8);pins=5;cycles(8);
  if(dut.gallery.KEY3_N!==0 || dut.engine.KEY3_N!==1)$fatal(1,"SW3-off menu key routing");
  pins=7;cycles(8);sw3=1;cycles(8);
  // Short switch chatter must not change the accepted state.
  sw3=0;cycles(2);sw3=1;cycles(8);check(1,0);
  if(dut.gallery.gesture_enabled!==1 || dut.gallery.clock_enabled!==0)$fatal(1,"core control wiring");
  sw1=1;cycles(8);check(1,0);
  if(dut.gallery.clock_enabled!==1 || dut.gallery.SW4!==1)$fatal(1,"SW1 independent clock enable");
  sw1=0;cycles(2);sw1=1;cycles(8);
  if(dut.gallery.clock_enabled!==1)$fatal(1,"SW1 chatter escaped debounce");
  sw1=0;cycles(8);if(dut.gallery.clock_enabled!==0)$fatal(1,"SW1 disable");
  passed=1;$display("PASS full switches: actual SW1/SW2/SW3/SW4 independence, original camera key roles, menu restoration, held-key guard and no queued replay");$finish;
 end
 initial begin #100000;$fatal(1,"switch watchdog");end
endmodule

module museum_phase6_core #(parameter EXTERNAL_GESTURE=0)(input sys_clk,sys_rst_n,KEY2_N,KEY3_N,KEY4_N,SW4,
 output SD_CLK,inout SD_CMD,input [3:0] SD_DAT,output HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,HDMI_DDC_SCL,inout HDMI_DDC_SDA,
 input [7:0] gesture_events,input [23:0] gesture_overlay_rgb,input gesture_keys_blocked,clock_enabled,gesture_enabled,
 output gesture_pixel_clk,gesture_pixel_rst,gesture_de,gesture_frame_start,gesture_ready,
 output [9:0] gesture_x,gesture_y,output [23:0] gesture_base_rgb,output [3:0] gesture_page);
 reg [3:0] test_page=7;
 assign gesture_pixel_clk=sys_clk;assign gesture_pixel_rst=!sys_rst_n;assign gesture_de=1;
 assign gesture_frame_start=0;assign gesture_ready=1;assign gesture_x=0;assign gesture_y=0;assign gesture_base_rgb=24'hf4eee4;assign gesture_page=test_page;
 assign SD_CLK=0;assign HDMI_CLK_P=0;assign HDMI_D0_P=0;assign HDMI_D1_P=0;assign HDMI_D2_P=0;assign HDMI_DDC_SCL=1;
endmodule
module camera_gesture_engine(input sys_clk,sys_rst_n,pixel_clk,pixel_rst,CAM_PCLK,CAM_VSYNC,CAM_HREF,input [7:0] CAM_D,
 inout CAM_SCL,CAM_SDA,output CAM_PWDN,CAM_RESET_N,UART_TX,input KEY2_N,KEY3_N,KEY4_N,
 input maintenance,controls_blocked,gesture_enabled,preview_enabled,de,frame_start,nav_ready,
 input [9:0] x,y,input [23:0] base_rgb,output [23:0] overlay_rgb,output reg [7:0] nav_events=0,output [3:0] LED);
 assign CAM_PWDN=0;assign CAM_RESET_N=sys_rst_n;assign UART_TX=1;assign LED=0;assign overlay_rgb=base_rgb;
endmodule

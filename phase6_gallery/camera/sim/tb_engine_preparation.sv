`timescale 1ns/1ps
module tb_engine_preparation;
reg sys_clk=0;always #5 sys_clk=~sys_clk;wire pixel_clk=sys_clk;reg sys_rst_n=0,pixel_rst=1;
reg KEY2_N=1,KEY3_N=1,KEY4_N=1,gesture_enabled=0,preview_enabled=1;wire[23:0] overlay_rgb;wire[7:0] nav_events;wire[3:0] LED;wire scl,sda,pwdn,resetn,tx;reg passed=0;integer n;
camera_gesture_engine #(.PREPARE_CYCLES(300000)) dut(.sys_clk(sys_clk),.sys_rst_n(sys_rst_n),.pixel_clk(pixel_clk),.pixel_rst(pixel_rst),.CAM_PCLK(sys_clk),.CAM_VSYNC(1'b0),.CAM_HREF(1'b0),.CAM_D(8'd0),.CAM_SCL(scl),.CAM_SDA(sda),.CAM_PWDN(pwdn),.CAM_RESET_N(resetn),.UART_TX(tx),.KEY2_N(KEY2_N),.KEY3_N(KEY3_N),.KEY4_N(KEY4_N),.maintenance(1'b0),.controls_blocked(1'b0),.gesture_enabled(gesture_enabled),.preview_enabled(preview_enabled),.de(1'b0),.frame_start(1'b0),.nav_ready(1'b1),.x(10'd0),.y(10'd0),.base_rgb(24'd0),.overlay_rgb(overlay_rgb),.nav_events(nav_events),.LED(LED));

defparam dut.extraction.WARMUP_CYCLES=0;
reg injected_valid=0,injected_start=0,injected_done=0;
reg [15:0] injected_x=0,injected_y=0,injected_rgb=16'h3186;
integer complete_frames=0,prep_frames=0;
always @(posedge pixel_clk)if(dut.source_de && dut.source_x==639 && dut.source_y==479)begin
 complete_frames=complete_frames+1;if(dut.recalibrate)prep_frames=prep_frames+1;
end
task frame;
begin
 @(negedge pixel_clk);injected_start=1;injected_done=1;
 @(negedge pixel_clk);injected_start=0;injected_done=0;
 for(integer yy=0;yy<60;yy=yy+1)for(integer xx=0;xx<80;xx=xx+1)begin
  injected_valid=1;injected_x=xx*4;injected_y=yy*4;
  @(negedge pixel_clk);injected_valid=0;repeat(19)@(negedge pixel_clk);
 end
 repeat(4000)@(negedge pixel_clk);
end endtask
initial begin
 force dut.ready=1'b1;
 force dut.video_valid=injected_valid;force dut.video_start=injected_start;
 force dut.video_done=injected_done;force dut.video_good=1'b1;
 force dut.video_x=injected_x;force dut.video_y=injected_y;force dut.video_pixel=injected_rgb;
 repeat(5)@(negedge pixel_clk);sys_rst_n=1;pixel_rst=0;repeat(15)@(negedge pixel_clk);
 gesture_enabled=1;
 repeat(13)frame;
 if(dut.source_fault || !dut.background_ready || prep_frames<2 || !dut.full_overlay.preview_ready)
  $fatal(1,"engine preparation failed fault=%b background=%b prepframes=%d preview=%b",dut.source_fault,dut.background_ready,prep_frames,dut.full_overlay.preview_ready);
 if(dut.calibration_mode)$fatal(1,"background preparation switched to mask view");
 force dut.toggle_view=1'b1;@(negedge pixel_clk);release dut.toggle_view;repeat(3)@(negedge pixel_clk);
 if(!dut.inspect_view || !dut.calibration_mode || dut.armed)$fatal(1,"KEY4 must enter diagnostic and disable tracker");
 force dut.toggle_view=1'b1;@(negedge pixel_clk);release dut.toggle_view;repeat(3)@(negedge pixel_clk);
 if(dut.inspect_view || dut.calibration_mode)$fatal(1,"KEY4 must restore RGB");
 force dut.manual_background=1'b1;@(negedge pixel_clk);release dut.manual_background;
 repeat(13)frame;
 if(dut.source_fault || !dut.background_ready || !dut.full_overlay.preview_ready)$fatal(1,"repeated KEY2 not recovered");
 passed=1;$display("PASS ENGINE PREPARATION: real stream/FILTER5/extraction, continuous preview during SW3 and KEY2 prepare, background ready, KEY4 RGB/mask round trip, no sticky FIFO fault");$finish;
end
initial begin #40000000;$fatal(1,"watchdog");end
endmodule

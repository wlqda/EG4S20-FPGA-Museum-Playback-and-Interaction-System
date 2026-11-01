`timescale 1ns/1ps
module EG_LOGIC_BUFG(input i,output o);assign o=i;endmodule
module tb_gesture_prepare;
reg sys_clk=0;always #5 sys_clk=~sys_clk;wire pixel_clk=sys_clk;reg sys_rst_n=0,pixel_rst=1;
reg KEY2_N=1,KEY3_N=1,KEY4_N=1,gesture_enabled=0,preview_enabled=1;wire[23:0] overlay_rgb;wire[7:0] nav_events;wire[3:0] LED;wire scl,sda,pwdn,resetn,tx;reg passed=0;integer n;
camera_gesture_engine #(.PREPARE_CYCLES(10)) dut(.sys_clk(sys_clk),.sys_rst_n(sys_rst_n),.pixel_clk(pixel_clk),.pixel_rst(pixel_rst),.CAM_PCLK(sys_clk),.CAM_VSYNC(1'b0),.CAM_HREF(1'b0),.CAM_D(8'd0),.CAM_SCL(scl),.CAM_SDA(sda),.CAM_PWDN(pwdn),.CAM_RESET_N(resetn),.UART_TX(tx),.KEY2_N(KEY2_N),.KEY3_N(KEY3_N),.KEY4_N(KEY4_N),.maintenance(1'b0),.controls_blocked(1'b0),.gesture_enabled(gesture_enabled),.preview_enabled(preview_enabled),.de(1'b0),.frame_start(1'b0),.nav_ready(1'b1),.x(10'd0),.y(10'd0),.base_rgb(24'd0),.overlay_rgb(overlay_rgb),.nav_events(nav_events),.LED(LED));
task tick;begin @(posedge pixel_clk);#1;end endtask
task prepare;begin
n=0;while(dut.recalibrate && n<20)begin tick;n=n+1;if(nav_events!=0 || LED[2])$fatal(1,"gesture accepted before preparation");end
if(n<10 || n>12)$fatal(1,"preparation duration %d",n);
repeat(3)tick;if(dut.background_ready || dut.armed)$fatal(1,"false ready before background frames");
end endtask
initial begin
force dut.ready=1'b1;
repeat(5)tick;@(negedge pixel_clk);sys_rst_n=1;pixel_rst=0;repeat(15)tick;
if(dut.recalibrate)$fatal(1,"off mode starts acquisition");
@(negedge pixel_clk);gesture_enabled=1;#1;if(!dut.recalibrate)$fatal(1,"SW3 rising edge not acquired");prepare;
repeat(5)tick;if(dut.recalibrate)$fatal(1,"repeated acquisition while enabled");
@(negedge pixel_clk);force dut.manual_background=1'b1;tick;@(negedge pixel_clk);release dut.manual_background;prepare;
@(negedge pixel_clk);gesture_enabled=0;repeat(3)tick;if(dut.recalibrate)$fatal(1,"disabled preparation remains");
@(negedge pixel_clk);gesture_enabled=1;#1;if(!dut.recalibrate)$fatal(1,"second SW3 enable failed");prepare;
passed=1;$display("PASS SW3 preparation: first/repeated enable, manual KEY2 request, held guard interval, no false ready/navigation");$finish;
end
initial begin #100000;$fatal(1,"watchdog");end
endmodule

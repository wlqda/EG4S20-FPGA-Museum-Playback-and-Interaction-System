// Current museum pipeline plus the archived 3939bd6 camera recognizer.
module museum_phase6_unified_top(input sys_clk,sys_rst_n,KEY2_N,KEY3_N,KEY4_N,SW1,SW2,SW3,SW4,
 output SD_CLK,inout SD_CMD,input [3:0] SD_DAT,
 output HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,HDMI_DDC_SCL,inout HDMI_DDC_SDA,
 input CAM_PCLK,CAM_VSYNC,CAM_HREF,input [7:0] CAM_D,
 inout CAM_SCL,CAM_SDA,output CAM_PWDN,CAM_RESET_N,UART_TX,output [3:0] LED);
 wire pixel_clk,pixel_rst,de,frame_start,ready,blocked;
 wire [9:0] x,y;wire [23:0] base_rgb,overlay_rgb;wire [7:0] events;
 wire [3:0] page;wire [2:0] museum_keys_n,camera_keys_n;
 wire gesture_enabled,preview_enabled,clock_enabled;
 museum_slide_switch clock_switch(.clk(pixel_clk),.rst(pixel_rst),.switch_in(SW1),.enabled(clock_enabled));
 museum_slide_switch gesture_switch(.clk(pixel_clk),.rst(pixel_rst),.switch_in(SW3),.enabled(gesture_enabled));
 museum_slide_switch preview_switch(.clk(pixel_clk),.rst(pixel_rst),.switch_in(SW2),.enabled(preview_enabled));
 museum_camera_key_modes key_modes(.clk(pixel_clk),.rst(pixel_rst),.gesture_enabled(gesture_enabled),.keys_n({KEY4_N,KEY3_N,KEY2_N}),
  .museum_keys_n(museum_keys_n),.camera_keys_n(camera_keys_n),.menu_blocked(blocked));
 // DOWN leaves attract/slideshow mode. Physical KEY4 retains the original zoom.
 wire [7:0] routed_events=!gesture_enabled ? 8'd0 : page==7 && events[2] ? 8'h08 : events;
 museum_phase6_core #(.EXTERNAL_GESTURE(1)) gallery(.sys_clk(sys_clk),.sys_rst_n(sys_rst_n),
  .KEY2_N(museum_keys_n[0]),.KEY3_N(museum_keys_n[1]),.KEY4_N(museum_keys_n[2]),.SW4(SW4),
  .SD_CLK(SD_CLK),.SD_CMD(SD_CMD),.SD_DAT(SD_DAT),.HDMI_CLK_P(HDMI_CLK_P),
  .HDMI_D2_P(HDMI_D2_P),.HDMI_D1_P(HDMI_D1_P),.HDMI_D0_P(HDMI_D0_P),
  .HDMI_DDC_SCL(HDMI_DDC_SCL),.HDMI_DDC_SDA(HDMI_DDC_SDA),
  .clock_enabled(clock_enabled),.gesture_enabled(gesture_enabled),
  .gesture_events(routed_events),.gesture_overlay_rgb(overlay_rgb),.gesture_keys_blocked(blocked),
  .gesture_pixel_clk(pixel_clk),.gesture_pixel_rst(pixel_rst),.gesture_de(de),
  .gesture_frame_start(frame_start),.gesture_ready(ready),.gesture_x(x),.gesture_y(y),
  .gesture_base_rgb(base_rgb),.gesture_page(page));
 camera_gesture_engine engine(.sys_clk(sys_clk),.sys_rst_n(sys_rst_n),.pixel_clk(pixel_clk),.pixel_rst(pixel_rst),
  .CAM_PCLK(CAM_PCLK),.CAM_VSYNC(CAM_VSYNC),.CAM_HREF(CAM_HREF),.CAM_D(CAM_D),
  .CAM_SCL(CAM_SCL),.CAM_SDA(CAM_SDA),.CAM_PWDN(CAM_PWDN),.CAM_RESET_N(CAM_RESET_N),.UART_TX(UART_TX),
  .KEY2_N(camera_keys_n[0]),.KEY3_N(camera_keys_n[1]),.KEY4_N(camera_keys_n[2]),
  .maintenance(1'b0),.controls_blocked(1'b0),.gesture_enabled(gesture_enabled),.preview_enabled(preview_enabled),
  .de(de),.frame_start(frame_start),.nav_ready(ready),
  .x(x),.y(y),.base_rgb(base_rgb),.overlay_rgb(overlay_rgb),.nav_events(events),.LED(LED));
endmodule

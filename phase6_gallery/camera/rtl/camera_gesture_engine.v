// Headless camera analysis sharing the Gallery pixel clock and HDMI pipeline.
module camera_gesture_engine #(parameter integer PREPARE_CYCLES=50000000)(
 input wire sys_clk,sys_rst_n,pixel_clk,pixel_rst,
 input wire CAM_PCLK,CAM_VSYNC,CAM_HREF,input wire [7:0] CAM_D,
 inout wire CAM_SCL,CAM_SDA,output wire CAM_PWDN,CAM_RESET_N,UART_TX,
 input wire KEY2_N,KEY3_N,KEY4_N,input wire maintenance,controls_blocked,gesture_enabled,preview_enabled,input wire de,frame_start,nav_ready,
 input wire [9:0] x,y,input wire [23:0] base_rgb,
 output wire [23:0] overlay_rgb,output wire [7:0] nav_events,output wire [3:0] LED);
 // Symmetric vertical expansion; keep the acquisition zone unchanged.
 localparam integer ROI_Y0=16,ROI_Y1=464;
 wire camera_clk,pclk;
 EG_LOGIC_BUFG camera_clock(.i(sys_clk),.o(camera_clk));
 EG_LOGIC_BUFG pclk_buffer(.i(CAM_PCLK),.o(pclk));
 reg [3:0] reset_pipe=15;
 always @(posedge camera_clk or negedge sys_rst_n)
  if(!sys_rst_n)reset_pipe<=15;else reset_pipe<={reset_pipe[2:0],1'b0};
 wire rst=reset_pipe[3];
 wire bus_start,bus_read,bus_busy,bus_done,ready;
 wire [15:0] bus_addr;wire [7:0] bus_write,bus_data;wire [2:0] bus_error;
 camera_config_controller #(.TEST_PATTERN(0),.SIMPLE_AWB(1)) config_control(
  .clk(camera_clk),.rst(rst),.cam_pwdn(CAM_PWDN),.cam_reset_n(CAM_RESET_N),
  .bus_start(bus_start),.bus_read(bus_read),.bus_addr(bus_addr),.bus_write(bus_write),
  .bus_busy(bus_busy),.bus_done(bus_done),.bus_data(bus_data),.bus_error(bus_error),
  .complete(),.ready(ready),.error(),.chip_id(),.failed_addr(),.actual_data(),.expected_data(),.index());
 camera_sccb_master #(.BUS_HZ(10000),.TIMEOUT_CYCLES(2500000)) bus(
  .clk(camera_clk),.rst(rst),.start(bus_start),.read_not_write(bus_read),
  .register_addr(bus_addr),.write_data(bus_write),.scl(CAM_SCL),.sda(CAM_SDA),
  .busy(bus_busy),.done(bus_done),.read_data(bus_data),.error(bus_error),.error_byte());
 wire frame_hold=rst || !ready;
 (* async_reg="true" *) reg [3:0] pclk_reset_pipe=15;
 always @(posedge pclk or posedge frame_hold)
  if(frame_hold)pclk_reset_pipe<=15;else pclk_reset_pipe<={pclk_reset_pipe[2:0],1'b0};
 wire capture_rst=pclk_reset_pipe[3];
 wire display_hold=frame_hold || pixel_rst;
 (* async_reg="true" *) reg [3:0] pixel_reset_pipe=15;
 always @(posedge pixel_clk or posedge display_hold)
  if(display_hold)pixel_reset_pipe<=15;else pixel_reset_pipe<={pixel_reset_pipe[2:0],1'b0};
 wire analysis_rst=pixel_reset_pipe[3];
 wire video_valid,video_start,video_done,video_good;wire [15:0] video_pixel,video_x,video_y;
 wire dvp_locked;
 camera_dvp_auto_monitor #(.BYTE_SWAP(1)) monitor(.pclk(pclk),.rst(capture_rst),
  .vsync(CAM_VSYNC),.href(CAM_HREF),.data(CAM_D),.locked(dvp_locked),.low_active(),.stats(),
  .pixel_valid(video_valid),.frame_start(video_start),.frame_done(video_done),.frame_good(video_good),
  .pixel(video_pixel),.pixel_x(video_x),.pixel_y(video_y));
 wire recalibrate,capture,toggle_view,manual_background;
 reg gesture_last;reg [25:0] prepare_count;
 always @(posedge pixel_clk)begin
  if(analysis_rst || !gesture_enabled)prepare_count<=0;
  else if(!gesture_last || manual_background)prepare_count<=PREPARE_CYCLES;
  else if(prepare_count!=0)prepare_count<=prepare_count-1'b1;
 end
 always @(posedge pixel_clk)if(analysis_rst)gesture_last<=0;else gesture_last<=gesture_enabled;
 assign recalibrate=manual_background || (gesture_enabled && !gesture_last) || prepare_count!=0;
 camera_background_button background_button(.clk(pixel_clk),.rst(analysis_rst),.key_n(KEY2_N),.pulse(manual_background));
 camera_background_button capture_button(.clk(pixel_clk),.rst(analysis_rst),.key_n(KEY3_N),.pulse(capture));
 camera_background_button view_button(.clk(pixel_clk),.rst(analysis_rst),.key_n(KEY4_N),.pulse(toggle_view));
 wire source_de,source_fresh,source_abort,source_fault,source_done;
 wire [9:0] source_x,source_y;wire [23:0] source_rgb;
 camera_source_stream source_stream(.wr_clk(pclk),.wr_rst(capture_rst),
  .pixel_valid(video_valid),.frame_start(video_start),.frame_done(video_done),.frame_good(video_good),
  .pixel(video_pixel),.pixel_x(video_x),.pixel_y(video_y),.rd_clk(pixel_clk),.rd_rst(analysis_rst),
  .recalibrate(recalibrate),.processing_done(source_done),.de(source_de),.fresh_frame(source_fresh),
  .abort_frame(source_abort),.x(source_x),.y(source_y),.rgb(source_rgb),.stream_fault(source_fault));
 // Hold extraction reset until the first whole source frame after preparation.
 // The preview sees every complete source frame, including the preparation window.
 reg extraction_frame;
 always @(posedge pixel_clk)begin
  if(analysis_rst || recalibrate || source_abort)extraction_frame<=0;
  else if(source_fresh)extraction_frame<=1;
 end
 wire extraction_hold=recalibrate || source_abort || (!extraction_frame && !source_fresh);
 wire background_ready,mask_valid;wire [6:0] mask_x;wire [5:0] mask_y;wire [2:0] mask_bits;
 wire pose_sample,candidate_valid,clipped;wire [31:0] pose_id;wire [143:0] counts;wire [12:0] area;
 wire [3:0] edges;wire [9:0] candidate_x,candidate_y;wire [223:0] analysis_status;
 // Packed diagnostic suffix: {left,right,top,bottom}, each 10 bits.
 wire [9:0] candidate_width=analysis_status[29:20]-analysis_status[39:30]+1'b1;
 wire [9:0] candidate_height=analysis_status[9:0]-analysis_status[19:10]+1'b1;
 wire armed,event_valid;wire [2:0] stage,error,pose,event_direction;
 wire identity_state=stage==1 || stage==2 || stage==3;
 wire [40:0] selection_reference;
 camera_selection_reference identity_reference(.clk(pixel_clk),
  .reset(analysis_rst || recalibrate || source_abort || capture || toggle_view || !gesture_enabled),
  .identity_state(identity_state),.sample_tick(pose_sample),.candidate_valid(candidate_valid),
  .cx(candidate_x),.cy(candidate_y),.width(candidate_width),.height(candidate_height),
  .selection_reference(selection_reference));
 camera_foreground_debug #(.ROI_Y0(ROI_Y0),.ROI_Y1(ROI_Y1),.PALM_FILTER(1),.TRACK_FILTER(0),.SOURCE_MODE(1),.SKIN_RECONSTRUCT(1),
  .SPATIAL_SCENE_GATE(1),.MAX_AREA(2400),.PALM_MAX_ASPECT(4),.POSE_FEATURES(1),.BACKGROUND_RAM_STYLE("bram_9k"),.IDENTITY_SELECT(1),.BINARY_FILTER(5)) extraction(
  .clk(pixel_clk),.rst(analysis_rst),.have_frame(1'b1),.recalibrate(extraction_hold),.fresh_frame(source_fresh),
  .pipeline_rates(32'd0),.pipeline_rates_valid(1'b0),.de(source_de),.hs(1'b1),.vs(1'b1),
  .selection_reference(selection_reference),
  .x(source_x),.y(source_y),.rgb(source_rgb),.out_de(),.out_hs(),.out_vs(),.out_rgb(),
  .background_ready(background_ready),.target_valid(),.centroid_x(candidate_x),.centroid_y(candidate_y),.target_area(),
  .processing_done(source_done),.mask_valid(mask_valid),.mask_x(mask_x),.mask_y(mask_y),.mask_bits(mask_bits),.analysis_status(analysis_status),
  .pose_sample(pose_sample),.pose_valid(candidate_valid),.pose_clipped(clipped),.pose_id(pose_id),.pose_counts(counts),.pose_area(area),.pose_edges(edges));
 wire [31:0] event_sequence;wire overflow,target_visible;wire [9:0] origin_x,origin_y;
 reg inspect_view;
 always @(posedge pixel_clk)if(analysis_rst || recalibrate || !gesture_enabled)inspect_view<=0;else if(toggle_view)inspect_view<=!inspect_view;
 camera_swipe_tracker tracker(.clk(pixel_clk),.rst(analysis_rst),
  .enabled(gesture_enabled && background_ready && !source_fault && !source_abort && !inspect_view && !toggle_view && !maintenance && !controls_blocked && nav_ready),
  .restart(capture),.epoch_reset(recalibrate || source_abort),.sample_valid(pose_sample),.candidate_valid(candidate_valid),
  .clipped(clipped),.edges(edges),.frame_id(pose_id),.cx(candidate_x),.cy(candidate_y),
  .width(candidate_width),.height(candidate_height),.state(stage),.reason(error),.direction(pose),
  .armed(armed),.event_valid(event_valid),.event_direction(event_direction),.event_sequence(event_sequence),
  .origin_x(origin_x),.origin_y(origin_y),.target_visible(target_visible));
 // Mirror only at the user-facing boundary; G1 retains raw camera directions.
 wire [2:0] user_direction=event_direction==2 ? 3 : event_direction==3 ? 2 : event_direction;
 camera_nav_adapter navigation(.clk(pixel_clk),.rst(analysis_rst),
  .enabled(gesture_enabled && background_ready && !source_fault && !source_abort && !inspect_view && !maintenance && !controls_blocked && !toggle_view && !capture && !recalibrate),
  .frame_start(frame_start),.ready(nav_ready),
  .event_valid(event_valid),.direction(user_direction),.events(nav_events),.overflow(overflow));
 wire [23:0] pose_overlay_rgb;
 // Background acquisition affects recognition readiness, not the chosen view.
 wire calibration_mode=gesture_enabled && inspect_view;
 camera_pose_overlay #(.SWIPE_MODE(1),.MIRROR_X(1),.INTEGRATED_STYLE(1),.ROI_Y0(ROI_Y0),.ROI_Y1(ROI_Y1)) full_overlay(
  .clk(pixel_clk),.rst(pixel_rst),.de(de),.x(x),.y(y),.base_rgb(base_rgb),
  .calibration(calibration_mode),.background_ready(background_ready),.fault(source_fault || overflow),
  .stage(stage),.collecting(stage==1),.error(error),.pose(pose),.armed(armed),.event_sequence(event_sequence),
  .mask_valid(mask_valid),.mask_x(mask_x),.mask_y(mask_y),.skin(mask_bits[1]),
  .preview_de(source_de),.preview_clear(analysis_rst || source_abort || source_fault),
  .preview_x(source_x),.preview_y(source_y),.preview_rgb(source_rgb),.nav_ready(nav_ready),
  .target_visible(target_visible),.target_x(candidate_x),.target_y(candidate_y),
  .preview_enable(preview_enabled),.diagnostics(calibration_mode),.recognition_enabled(gesture_enabled),
  .preparing(prepare_count!=0),.source_fault(source_fault),.nav_overflow(overflow),.rgb(pose_overlay_rgb));
 assign overlay_rgb=pose_overlay_rgb;
 assign LED={source_fault || overflow,armed,target_visible,background_ready};
 // D12 -> CH340 RXD. 73-byte ASCII record per analysed frame / event / heartbeat.
 camera_telemetry_uart #(.CLK_HZ(25000000),.BAUD(115200),.HEARTBEAT_CYCLES(12500000)) telemetry(
  .clk(pixel_clk),.rst(analysis_rst),
  .frame_id(pose_id),.event_sequence(event_sequence),
  .stage(stage),.reason(error),.pose(pose),.event_direction(event_direction),
  .armed(armed),.target_visible(target_visible),.candidate_valid(candidate_valid),.clipped(clipped),
  .background_ready(background_ready),.source_fault(source_fault),.nav_overflow(overflow),.dvp_locked(dvp_locked),
  .cx(candidate_x),.cy(candidate_y),.width(candidate_width),.height(candidate_height),
  .area(area),.edges(edges),.sample_tick(pose_sample),.event_valid(event_valid),.tx(UART_TX));
endmodule

// Same-clock reference updated only after the tracker accepts a result. It is
// invalid immediately outside CONFIRM/ARMED/TRACK, including RETURN and reset.
module camera_selection_reference(input wire clk,reset,identity_state,sample_tick,candidate_valid,
 input wire [9:0] cx,cy,width,height,output wire [40:0] selection_reference);
 reg reference_have,result_pending;
 reg [9:0] reference_x,reference_y,reference_width,reference_height;
 assign selection_reference={reference_have && identity_state,reference_x,reference_y,reference_width,reference_height};
 always @(posedge clk)begin
  if(reset)begin
   reference_have<=0;result_pending<=0;
   reference_x<=0;reference_y<=0;reference_width<=0;reference_height<=0;
  end else begin
   result_pending<=sample_tick;
   if(!identity_state)reference_have<=0;
   else if(result_pending && candidate_valid)begin
    reference_have<=1;reference_x<=cx;reference_y<=cy;
    reference_width<=width;reference_height<=height;
   end
  end
 end
endmodule

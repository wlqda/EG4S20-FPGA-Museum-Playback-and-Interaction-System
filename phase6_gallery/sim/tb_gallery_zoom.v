`timescale 1ns/1ps
module tb_gallery_zoom;
 reg clk=0;always #5 clk=~clk;
 reg rst=1;reg [1:0] zoom=0;reg line_toggle=0;reg [8:0] line_number=0;
 wire [20:0] word_addr;wire request;wire write_req;wire [31:0] write_data;
 wire frame_toggle;wire [1:0] frame_bank;wire [15:0] active_index;
 wire [7:0] memory_error;wire [31:0] pixel_word;
 wire [8:0] line0_number,line1_number;wire line0_epoch,line1_epoch,line0_ready,line1_ready,line_ack;
 museum_gallery_image_memory memory(.clk(clk),.rst(rst),.pixel_clk(clk),.pixel_rst(rst),.zoom(zoom),
  .begin_valid(1'b0),.begin_ready(),.image_index(16'd0),.image_width(16'd640),.image_height(16'd480),
  .pixel_valid(1'b0),.pixel_ready(),.pixel_addr(19'd0),.pixel_rgb(24'd0),
  .end_valid(1'b0),.end_ready(),.abort(1'b0),.frame_toggle(frame_toggle),.frame_bank(frame_bank),
  .display_ack(1'b0),.active_index(active_index),.error(memory_error),
  .line_toggle(line_toggle),.line_number(line_number),.line_frame_bank(2'd0),
  .pixel_address(11'd0),.pixel_word(pixel_word),.line0_number(line0_number),.line1_number(line1_number),
  .line0_epoch(line0_epoch),.line1_epoch(line1_epoch),.line0_ready(line0_ready),.line1_ready(line1_ready),.line_ack(line_ack),
  .req(request),.write_req(write_req),.word_addr(word_addr),.write_data(write_data),
  .memory_ready(1'b1),.controller_busy(1'b0),.controller_done(1'b0),.read_valid(1'b0),
  .write_take(1'b0),.request_accepted(1'b0),.read_data(32'd0));
 wire [10:0] pixel_address;wire [9:0] x,y;wire hs,vs,de;wire [23:0] rgb;
 museum_gallery_image_display #(.SHOW_STATUS(0)) display(.clk(clk),.rst(rst),.zoom(zoom),
  .frame_toggle(1'b0),.frame_bank(2'd0),.display_ack(),.display_bank(),
  .line_toggle(),.line_number(),.line_ack(1'b0),.line0_number(9'd0),.line1_number(9'd0),
  .line0_epoch(1'b0),.line1_epoch(1'b0),.line0_ready(1'b0),.line1_ready(1'b0),
  .pixel_address(pixel_address),.pixel_word(32'd0),.error_async(8'd0),.mounted_async(1'b0),
  .sd_stage_async(4'd0),.fs_stage_async(8'd0),.audio_due_toggle(1'b0),.audio_due_bank(2'd0),
  .audio_underflows(8'd0),.display_error(),.video_started(),.x(x),.y(y),.hs(hs),.vs(vs),.de(de),.rgb(rgb));
 reg passed=0;integer mode;
 task check_map;input integer z,expected_x,expected_y;begin
  @(negedge clk);rst=1;zoom=z;line_toggle=0;line_number=0;
  repeat(3)@(negedge clk);rst=0;
  repeat(6)@(negedge clk);
  line_toggle=1;
  repeat(12)@(negedge clk);
  display.h=0;
  #1;
  if(word_addr!==(21'h100000+expected_y*640) || memory.source_line!==expected_y || pixel_address[9:0]!==expected_x || !request || write_req)
   $fatal(1,"zoom %0d: source_y=%0d source_x=%0d request=%b",z,memory.source_line,pixel_address[9:0],request);
 end endtask
 initial begin
  check_map(0,0,0);
  check_map(1,160,120);
  check_map(2,240,180);
  passed=1;$display("PASS zoom mappings: 1x, 2x, 4x source line and pixel address");$finish;
 end
 initial begin #100000;$fatal(1,"watchdog");end
endmodule

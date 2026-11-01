// RGB888 double buffer, BL8 writes, two 640-word read lines.
// Frame banks occupy 0x100000 and 0x180000 in the 2M-word SDRAM.
module museum_gallery_image_memory(
 input clk,rst,pixel_clk,pixel_rst,input [1:0] zoom,
 input begin_valid,output begin_ready,input [15:0] image_index,image_width,image_height,
 input pixel_valid,output pixel_ready,input [18:0] pixel_addr,input [23:0] pixel_rgb,
 input end_valid,output end_ready,input abort,
 output reg frame_toggle,output reg [1:0] frame_bank,input display_ack,
 output reg [15:0] active_index,output reg [7:0] error,
 input line_toggle,input [8:0] line_number,input [1:0] line_frame_bank,
 input [10:0] pixel_address,output reg [31:0] pixel_word,
 output reg [8:0] line0_number,line1_number,
 output reg line0_epoch,line1_epoch,line0_ready,line1_ready,line_ack,
 output wire req,write_req,output wire [20:0] word_addr,output wire [31:0] write_data,
 input memory_ready,controller_busy,controller_done,read_valid,write_take,request_accepted,
 input [31:0] read_data
);
 localparam IDLE=0,START_W=1,WAIT_W=2,START_R=3,WAIT_R=4,PREP_R0=5,PREP_R1=6,PREP_R2=7;
 reg [2:0] state;reg loading,waiting_ack,write_bank;
 reg [15:0] saved_index;reg [18:0] received;
 reg [3:0] filled;reg [31:0] burst[0:7];reg [18:0] burst_addr;
 reg [2:0] send_index,read_index;
 reg [1:0] ack_pipe,lt_pipe;reg line_pending,requested_epoch;
 reg [1:0] zoom_meta,zoom_mem;
 reg [8:0] requested_line;reg [1:0] requested_bank;reg [6:0] line_burst;
 (* ram_style="bram_32k" *) reg [31:0] lines[0:2047];
 always @(posedge pixel_clk)pixel_word<=lines[pixel_address];
 wire [20:0] wr_base=write_bank ? 21'h180000 : 21'h100000;
 wire [20:0] rd_base=requested_bank[0] ? 21'h180000 : 21'h100000;
 assign begin_ready=!loading && !waiting_ack && filled==0 && state==IDLE && memory_ready;
 assign pixel_ready=loading && filled<8;
 assign end_ready=loading && filled==0 && state==IDLE;
 assign req=(state==START_W || state==START_R) && memory_ready && !controller_busy;
 assign write_req=state==START_W;
 wire [8:0] source_line=zoom_mem==2 ? 9'd180+(requested_line>>2) :
                         zoom_mem==1 ? 9'd120+(requested_line>>1) : requested_line;
 reg [8:0] source_line_q;reg [18:0] row_offset;
 always @(posedge clk)begin source_line_q<=source_line;row_offset<=source_line_q*19'd640;end
 wire [18:0] read_offset=row_offset+{line_burst,3'b000};
 assign word_addr=write_req ? {wr_base[20:19],burst_addr} : {rd_base[20:19],read_offset};
 assign write_data=burst[send_index];
 always @(posedge clk)begin
  if(read_valid)lines[{requested_line[0],line_burst,read_index}]<=read_data;
  if(rst)begin
   state<=IDLE;loading<=0;waiting_ack<=0;write_bank<=0;received<=0;filled<=0;
   saved_index<=0;active_index<=0;error<=0;burst_addr<=0;send_index<=0;read_index<=0;
   frame_toggle<=0;frame_bank<=0;ack_pipe<=0;lt_pipe<=0;line_pending<=0;zoom_meta<=0;zoom_mem<=0;
   requested_line<=0;requested_bank<=0;requested_epoch<=0;line_burst<=0;
   line0_number<=0;line1_number<=0;line0_epoch<=0;line1_epoch<=0;
   line0_ready<=0;line1_ready<=0;line_ack<=0;
  end else begin
   zoom_meta<=zoom;zoom_mem<=zoom_meta;
   ack_pipe<={ack_pipe[0],display_ack};lt_pipe<={lt_pipe[0],line_toggle};
   if(waiting_ack && ack_pipe[1]==frame_toggle)waiting_ack<=0;
   if(begin_valid && begin_ready)begin
    saved_index<=image_index;received<=0;filled<=0;
    if(image_width!=640 || image_height!=480)begin error<=8'h51;loading<=1;end
    else begin error<=0;loading<=1;end
   end
   if(pixel_valid && pixel_ready)begin
    burst[filled[2:0]]<={8'd0,pixel_rgb};if(error==0)filled<=filled+1'b1;else filled<=0;received<=received+1'b1;
    if(filled==0)begin burst_addr<=pixel_addr;if(pixel_addr[2:0]!=0)error<=8'h52;end
    else if(pixel_addr!={burst_addr[18:3],filled[2:0]})error<=8'h52;
    if(pixel_addr>=307200 || received>=307200)error<=8'h52;
   end
   if(abort)begin loading<=0;error<=8'h53;if(state!=WAIT_W)filled<=0;end
   if(end_valid && end_ready)begin
    loading<=0;
    if(received!=307200 || error!=0)error<=8'h54;
    else begin
     frame_bank<={1'b0,write_bank};frame_toggle<=~frame_toggle;
     active_index<=saved_index;waiting_ack<=1;write_bank<=~write_bank;
    end
   end
   if(lt_pipe[1]!=line_ack && !line_pending)begin
    requested_line<=line_number;requested_bank<=line_frame_bank;
    requested_epoch<=display_ack;line_burst<=0;line_pending<=1;
    if(line_number[0])line1_ready<=0;else line0_ready<=0;
   end
   if(write_take)send_index<=send_index+1'b1;
   if(read_valid)read_index<=read_index+1'b1;
   case(state)
    IDLE: if(line_pending)begin read_index<=0;state<=PREP_R0;end
     else if(filled==8 && loading && error==0)begin send_index<=0;state<=START_W;end
    PREP_R0:state<=PREP_R1;
    PREP_R1:state<=PREP_R2;
    PREP_R2:state<=START_R;
    START_W: if(abort)begin state<=IDLE;filled<=0;end
     else if(request_accepted)state<=WAIT_W;
    WAIT_W: if(controller_done)begin filled<=0;state<=IDLE;end
    START_R: if(request_accepted)state<=WAIT_R;
    WAIT_R: if(controller_done)begin
     if(line_burst==79)begin
      line_pending<=0;line_ack<=lt_pipe[1];state<=IDLE;
      if(requested_line[0])begin line1_number<=requested_line;line1_epoch<=requested_epoch;line1_ready<=1;end
      else begin line0_number<=requested_line;line0_epoch<=requested_epoch;line0_ready<=1;end
     end else begin line_burst<=line_burst+1'b1;read_index<=0;state<=START_R;end
    end
   endcase
  end
 end
endmodule

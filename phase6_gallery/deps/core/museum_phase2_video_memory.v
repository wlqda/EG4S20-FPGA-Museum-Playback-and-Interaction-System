// SD bytes -> burst FIFO -> three SDRAM frames; SDRAM -> two video line buffers.
// A stable bank mailbox permits writing the next frame before display ACK.
// Publish only after all frame sectors have passed the SD data CRC.
module museum_phase2_video_memory #(parameter WORDS_PER_FRAME=115200)(
 input clk,rst,pixel_clk,pixel_rst,input [7:0] data,input valid,
 input sector_commit,input stream_error,
 output reg resume_ok,output reg frame_toggle,output reg [1:0] frame_bank,input display_ack,
 input line_toggle,input [8:0] line_number,input [1:0] line_frame_bank,
 input [9:0] pixel_address,output reg [31:0] pixel_word,
 output reg [8:0] line0_number,line1_number,
 output reg line0_epoch,line1_epoch,output reg line0_ready,line1_ready,
 output reg line_ack,output reg [7:0] error,
 output req,output is_write,output [20:0] bus_addr,output [31:0] bus_data,
 input memory_ready,controller_busy,controller_done,read_valid,write_take,request_accepted,
 input [31:0] read_data
);
 reg [1:0] byte_phase;
 reg [23:0] pack;
 wire fifo_push=valid && byte_phase==3;
 wire [31:0] fifo_data={pack[7:0],data,pack[23:8]};
 wire [31:0] fifo_q;
 wire [10:0] fifo_used;
 reg fifo_pop;
 word_fifo fifo(.clk(clk),.rst(rst),.push(fifo_push),.pop(fifo_pop),
  .data(fifo_data),.q(fifo_q),.used(fifo_used));
 reg [16:0] words_received,words_written;
 reg [1:0] write_bank;
 reg waiting_ack,publishing;
 localparam SECTORS_PER_FRAME=WORDS_PER_FRAME/128;
 reg [9:0] sectors_verified;
 reg [1:0] ack_pipe,lt_pipe;
 // A complete 512-byte sector must fit; the SD host pauses between sectors.
 always @(posedge clk) begin
  if(rst) resume_ok<=0;
  else resume_ok<=memory_ready && fifo_used<850 && words_received<WORDS_PER_FRAME &&
   !publishing && !stream_error && error==0;
 end
 localparam IDLE=0,FETCH=1,LOAD=2,START_W=3,WAIT_W=4,START_R=5,WAIT_R=6;
 reg [2:0] state;
 reg [31:0] burst[0:7];
 reg [3:0] load_index;
 reg [2:0] send_index,read_index;
 reg [8:0] requested_line;
 reg [1:0] requested_bank;
 reg requested_epoch;
 reg [5:0] line_burst;
 reg line_pending;
 assign is_write=state==START_W;
 assign req=(state==START_W || state==START_R) && !controller_busy && memory_ready;
 wire [20:0] wr_addr={1'b0,write_bank,18'b0}+words_written;
 wire [20:0] line_base={1'b0,requested_bank,18'b0}+requested_line*21'd320;
 wire [20:0] rd_addr=line_base+{line_burst,3'b000};
 assign bus_addr=is_write ? wr_addr : rd_addr;
 assign bus_data=burst[send_index];
 (* ram_style="bram_32k" *) reg [31:0] lines[0:1023];
 always @(posedge pixel_clk) pixel_word<=lines[pixel_address];
 always @(posedge clk) begin
  if(read_valid) lines[{requested_line[0],line_burst,read_index}]<=read_data;
  if(rst) begin
   byte_phase<=0;pack<=0;words_received<=0;words_written<=0;
   frame_toggle<=0;frame_bank<=0;write_bank<=0;waiting_ack<=0;publishing<=0;sectors_verified<=0;
   ack_pipe<=0;lt_pipe<=0;state<=IDLE;fifo_pop<=0;
   load_index<=0;send_index<=0;read_index<=0;requested_line<=0;
   requested_bank<=0;requested_epoch<=0;line_pending<=0;line_burst<=0;
   line0_number<=0;line1_number<=0;line0_epoch<=0;line1_epoch<=0;
   line0_ready<=0;line1_ready<=0;line_ack<=0;error<=0;
  end else begin
   fifo_pop<=0;
   ack_pipe<={ack_pipe[0],display_ack};lt_pipe<={lt_pipe[0],line_toggle};
   if(sector_commit && !stream_error) begin
    if(sectors_verified==SECTORS_PER_FRAME) error<=8'h43;
    else sectors_verified<=sectors_verified+1'b1;
   end
   if(valid) begin
    pack<={pack[15:0],data};byte_phase<=byte_phase+1'b1;
    if(fifo_push) begin
     if(fifo_used==1024 || words_received==WORDS_PER_FRAME) error<=8'h41;
     else words_received<=words_received+1'b1;
    end
   end
   if(words_received==WORDS_PER_FRAME && words_written==WORDS_PER_FRAME &&
      sectors_verified==SECTORS_PER_FRAME && state==IDLE && fifo_used==0 &&
      !waiting_ack && !publishing && !stream_error && error==0) publishing<=1;
   if(publishing && !stream_error && error==0) begin
    frame_bank<=write_bank;frame_toggle<=~frame_toggle;publishing<=0;waiting_ack<=1;
    // Strictly ordered 0 -> 1 -> 2 -> 0. At most one published frame and
    // one writing frame can exist, so the next bank is never being displayed.
    write_bank<=write_bank==2 ? 0 : write_bank+1'b1;
    words_received<=0;words_written<=0;sectors_verified<=0;
   end
   if(waiting_ack && ack_pipe[1]==frame_toggle) begin
    waiting_ack<=0;
   end
   if(lt_pipe[1]!=line_ack && !line_pending) begin
    requested_line<=line_number;requested_bank<=line_frame_bank;
    requested_epoch<=display_ack;line_burst<=0;line_pending<=1;
    if(line_number[0]) line1_ready<=0;else line0_ready<=0;
   end
   if(write_take) send_index<=send_index+1'b1;
   if(read_valid) read_index<=read_index+1'b1;
   case(state)
    IDLE: if(line_pending) begin state<=START_R;read_index<=0;end
     else if(fifo_used>=8) begin load_index<=0;state<=FETCH;end
    FETCH: begin fifo_pop<=1;state<=LOAD;end
    LOAD: begin
     burst[load_index]<=fifo_q;
     if(load_index==7) begin state<=START_W;send_index<=0;end
     else begin load_index<=load_index+1'b1;state<=FETCH;end
    end
    START_W: if(request_accepted) state<=WAIT_W;
    WAIT_W: if(controller_done) begin words_written<=words_written+8;state<=IDLE;end
    START_R: if(request_accepted) state<=WAIT_R;
    WAIT_R: if(controller_done) begin
     if(line_burst==39) begin
      line_pending<=0;line_ack<=lt_pipe[1];
      if(requested_line[0]) begin
       line1_number<=requested_line;line1_epoch<=requested_epoch;line1_ready<=1;
      end else begin
       line0_number<=requested_line;line0_epoch<=requested_epoch;line0_ready<=1;
      end
      state<=IDLE;
     end else begin line_burst<=line_burst+1'b1;read_index<=0;state<=START_R;end
    end
   endcase
  end
 end
endmodule

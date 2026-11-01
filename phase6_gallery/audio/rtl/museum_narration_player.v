// Pixel-domain command mailbox; memory-domain reader; independent 48 kHz playback.
// cmd_start/cmd_stop are pulses accepted only when cmd_ready. Payload is held
// until memory acknowledges drain + reset of the preceding session.
module museum_narration_player #(parameter PIXEL_HZ=25000000,SAMPLE_HZ=48000,FIFO_ADDR=12,USE_CACHED_INDEX=0)(
 input cached_done,input [7:0] cached_error,input [3:0] cached_present,
 input [31:0] cached_cluster,cached_size,cached_fat_lba,cached_data_lba,cached_max_cluster,
 input [7:0] cached_spc,input [2:0] cached_shift,output [1:0] cached_select,
 input mem_clk,mem_rst,pixel_clk,pixel_rst,
 input cmd_start,cmd_stop,input [1:0] exhibit,input paused,output cmd_ready,
 output playing,busy,output reg ended,output [7:0] error,
 output reg sample_valid,content_valid,output reg [23:0] sample_data,
 output reg [31:0] consumed_samples,output reg [7:0] underflows,
 output rd_req_valid,output [31:0] rd_lba,output [22:0] rd_count,
 input rd_req_ready,input [7:0] rd_data,input rd_valid,rd_sector_commit,rd_done,
 input [7:0] rd_error,output rd_resume);
 reg request,requested_play;reg [1:0] requested_exhibit;
 reg ack;(* async_reg="true" *) reg [1:0] ack_sync,req_sync;
 reg [2:0] mstate;localparam M_IDLE=0,M_DRAIN=1,M_RESET=2,M_LAUNCH=3,M_RUN=4;
 reg [4:0] reset_count;reg request_seen;reg play_m;reg [1:0] exhibit_m;
 wire reader_busy;wire [7:0] reader_error;
 wire [15:0] pcm;wire pcm_valid,pcm_last,pcm_ready;
 wire fifo_reset=mstate!=M_RUN;
 wire [16:0] fifo_data;wire fifo_valid,fifo_pop;
 reg started,starving;reg [31:0] phase;
 reg [7:0] error0,error1;
 wire [32:0] phase_next={1'b0,phase}+SAMPLE_HZ;
 wire tick=phase_next>=PIXEL_HZ;
 wire pending=request!=ack_sync[1];
 wire run_p=requested_play && !pending && !ended && error1==0;
 assign cmd_ready=!pending;
 assign error=error1;
 assign playing=run_p && started;
 assign busy=pending || (run_p && !started);
 assign fifo_pop=tick && run_p && !paused && fifo_valid;
 always @(posedge pixel_clk)begin
  if(pixel_rst)begin
   request<=0;requested_play<=0;requested_exhibit<=0;ack_sync<=0;
   phase<=0;sample_valid<=0;content_valid<=0;sample_data<=0;
   started<=0;ended<=0;consumed_samples<=0;underflows<=0;starving<=0;error0<=0;error1<=0;
  end else begin
   ack_sync<={ack_sync[0],ack};
   error0<=reader_error;error1<=error0;
   sample_valid<=0;content_valid<=0;
   if(tick)begin
    phase<=phase_next-PIXEL_HZ;sample_valid<=1;sample_data<=0;
    if(run_p && !paused)begin
     if(fifo_valid)begin
      sample_data<={fifo_data[15:0],8'd0};content_valid<=1;started<=1;starving<=0;
      consumed_samples<=consumed_samples+1'b1;
      if(fifo_data[16])ended<=1;
     end else if(started)begin
      starving<=1;if(!starving && underflows!=255)underflows<=underflows+1'b1;
     end
    end
   end else phase<=phase_next[31:0];
   if(cmd_ready && (cmd_start || cmd_stop))begin
    request<=~request;requested_play<=cmd_start && !cmd_stop;requested_exhibit<=exhibit;
    started<=0;ended<=0;consumed_samples<=0;underflows<=0;starving<=0;sample_data<=0;content_valid<=0;
   end
  end
 end
 always @(posedge mem_clk)begin
  if(mem_rst)begin
   req_sync<=0;ack<=0;request_seen<=0;play_m<=0;exhibit_m<=0;mstate<=M_IDLE;reset_count<=0;
  end else begin
   req_sync<={req_sync[0],request};
   case(mstate)
    M_IDLE,M_RUN:if(req_sync[1]!=request_seen)begin
     request_seen<=req_sync[1];play_m<=requested_play;exhibit_m<=requested_exhibit;mstate<=M_DRAIN;
    end
    M_DRAIN:if(!reader_busy)begin reset_count<=0;mstate<=M_RESET;end
    M_RESET:if(reset_count==31)begin
     if(play_m)mstate<=M_LAUNCH;else begin ack<=request_seen;mstate<=M_IDLE;end
    end else reset_count<=reset_count+1'b1;
    M_LAUNCH:begin mstate<=M_RUN;ack<=request_seen;end
    default:mstate<=M_IDLE;
   endcase
  end
 end
 museum_audio_reader #(.USE_CACHED_INDEX(USE_CACHED_INDEX)) reader(.clk(mem_clk),.rst(mem_rst || mstate==M_RESET),
  .cached_done(cached_done),.cached_error(cached_error),.cached_present(cached_present),
  .cached_cluster(cached_cluster),.cached_size(cached_size),.cached_fat_lba(cached_fat_lba),
  .cached_data_lba(cached_data_lba),.cached_max_cluster(cached_max_cluster),
  .cached_spc(cached_spc),.cached_shift(cached_shift),.cached_select(cached_select),
  .start(mstate==M_LAUNCH),.cancel(mstate==M_DRAIN),.exhibit(exhibit_m),
  .busy(reader_busy),.finished(),.error(reader_error),.pcm_data(pcm),.pcm_valid(pcm_valid),
  .pcm_last(pcm_last),.pcm_ready(pcm_ready),.total_samples(),
  .rd_req_valid(rd_req_valid),.rd_lba(rd_lba),.rd_count(rd_count),.rd_req_ready(rd_req_ready),
  .rd_data(rd_data),.rd_valid(rd_valid),.rd_sector_commit(rd_sector_commit),.rd_done(rd_done),
  .rd_error(rd_error),.rd_resume(rd_resume));
 museum_pcm_fifo #(.ADDR(FIFO_ADDR)) fifo(
  .wclk(mem_clk),.wrst(mem_rst || fifo_reset),.wdata({pcm_last,pcm}),
  .wvalid(pcm_valid && mstate==M_RUN),.wready(pcm_ready),
  .rclk(pixel_clk),.rrst(pixel_rst || pending || !requested_play),
  .rdata(fifo_data),.rvalid(fifo_valid),.rready(fifo_pop));
endmodule

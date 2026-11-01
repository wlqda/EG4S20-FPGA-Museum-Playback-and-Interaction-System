// Physical adaptation of lizhirui's 4-bit reader to Anlogic IO primitives.
module museum_phase1_sdio_host #(parameter SIMULATION=0, SD_CLK_DIV=3, RX_PIPE_DELAY=2)(input clk,rst,
 output SD_CLK,inout SD_CMD,input [3:0] SD_DAT,
 input read_req,input [31:0] read_lba,input [22:0] read_count,input resume_ok,
 output [3:0] debug_state,
 output ready,output [7:0] data,output valid,done,block_valid,output [7:0] error);
 wire card_clk_raw,cmd_out,cmd_oe;
 reg cmd_ddr,cmd_drive,cmd_sample,cmd_sync;
 reg [3:0] dat_sample,dat_sync;
 reg [3:0] dat_late;
 reg [3:0] dat_late_sync;
 // Give the data/CRC combinational path a full core period after capture.
 always @(posedge clk)dat_late_sync<=dat_late;
 wire [1:0] card_type;
 wire [3:0] card_state;
 wire busy,suspend,crc_error,high_speed_ok,switch_error;
 wire [3:0] crc_lanes;
 reg accepted;
 reg start_q;reg [31:0] sector_q;reg [22:0] count_q;
 reg [28:0] watchdog;
 reg timed_out;
 reg clock_out;
 // Forward the SD clock half a logic cycle after data changes. All input
 // sampling stays in the 100-MHz domain, avoiding a variable fabric clock.
 always @(negedge clk) begin
  if(rst)begin clock_out<=1;dat_late<=15;end
  else begin clock_out<=!card_clk_raw;dat_late<=SD_DAT;end
 end
 assign SD_CLK=clock_out;
 assign SD_CMD=cmd_drive ? cmd_ddr : 1'bz;
 always @(posedge clk) begin
  if(rst) begin cmd_ddr<=1;cmd_drive<=0;cmd_sample<=1;cmd_sync<=1;
   dat_sample<=15;dat_sync<=15;end
  else begin
   cmd_ddr<=cmd_out;cmd_drive<=cmd_oe;
   cmd_sample<=SD_CMD;cmd_sync<=cmd_sample;
   dat_sample<=SD_DAT;dat_sync<=dat_sample;
  end
 end
 // For CRC failures this diagnostic field identifies the failed DAT lanes.
 assign debug_state=crc_error ? crc_lanes : card_state;
 wire start=read_req && !accepted && ready && !busy;
 assign ready=!busy && !start_q && card_type==3 && high_speed_ok && error==0;
 assign error=crc_error ? 8'h13 : switch_error ? 8'h12 :
  (card_state==11 && card_type!=3) ? 8'h11 : timed_out ? 8'h14 : 8'h00;
 always @(posedge clk) begin
  if(rst) begin accepted<=0;watchdog<=0;timed_out<=0;start_q<=0;sector_q<=0;count_q<=0;end
  else begin
   start_q<=start;
   if(start)begin sector_q<=read_lba;count_q<=read_count;end
   if(!read_req) accepted<=0;else if(start) accepted<=1;
   if(valid || ready || (suspend && !resume_ok)) watchdog<=0;
   else if(watchdog==300000000) timed_out<=1;
   else watchdog<=watchdog+1'b1;
  end
 end
 // HS receive uses a later input sample; CMD6/default mode keep the old phase.
 wire [3:0] received_dat=(RX_PIPE_DELAY!=0 && high_speed_ok) ?
  (RX_PIPE_DELAY>=2 ? dat_late_sync : dat_late) : dat_sync;
 museum_phase1_sd_reader #(.CLK_DIV(SD_CLK_DIV),.SIMULATION(SIMULATION),.RX_PIPE_DELAY(RX_PIPE_DELAY)) reader(
  .clk(clk),.rstn(!rst),.sdclk(card_clk_raw),.sdcmdin(cmd_sync),
  .sdcmdout(cmd_out),.sdcmdoe(cmd_oe),.sddat(received_dat),
  .card_type(card_type),.card_stat(card_state),.rstart(start_q),
  .rsector(sector_q),.rsector_num(count_q),.rsuspend(suspend),
  .rresume(resume_ok),.rresume_ack(),.rbusy(busy),.rdone(done),
  .outen(valid),.outaddr(),.outbyte(data),.integrity_error(crc_error),
  .integrity_lanes(crc_lanes),
  .block_valid(block_valid),.high_speed_ok(high_speed_ok),.switch_error(switch_error));
endmodule

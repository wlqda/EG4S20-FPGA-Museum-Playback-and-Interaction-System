// One WAV file at a time. Requests are single-sector, so image and audio clients
// can interleave at every sector. Cancellation drains any accepted SD transaction.
module museum_audio_reader #(parameter USE_CACHED_INDEX=0)(
 input cached_done,input [7:0] cached_error,input [3:0] cached_present,
 input [31:0] cached_cluster,cached_size,cached_fat_lba,cached_data_lba,cached_max_cluster,
 input [7:0] cached_spc,input [2:0] cached_shift,output [1:0] cached_select,
 input clk,rst,start,cancel,input [1:0] exhibit,
 output busy,output reg finished,output reg [7:0] error,
 output [15:0] pcm_data,output pcm_valid,pcm_last,input pcm_ready,
 output [31:0] total_samples,
 output rd_req_valid,output [31:0] rd_lba,output [22:0] rd_count,
 input rd_req_ready,input [7:0] rd_data,input rd_valid,rd_sector_commit,rd_done,
 input [7:0] rd_error,output rd_resume);
 localparam IDLE=0,INIT=1,SCAN=2,OPEN=3,PRIME=4,REQ=5,WAIT=6,
  ADDR=7,FEED=8,REL=9,ADV=10,FREQ=11,FWAIT=12,FADDR=13,FCOPY=14,
  FCHK=15,NEXT=16,DRAIN=17,FLUSH=18,CLUSTER_WAIT=19,BASE_WAIT0=20,BASE_WAIT1=21,DATA_FETCH=22,FCHK_WAIT=23;
 reg [4:0] state;
 reg [1:0] selected; reg scan_pulse;
 wire index_rst=rst || state==INIT;
 wire scan_done,scan_busy;wire [7:0] scan_error;wire [3:0] present;
 wire [31:0] cluster_entry,size_entry,fat_lba,data_lba,max_cluster;
 wire [7:0] spc;wire [2:0] shift;
 wire idx_req,idx_release;wire [31:0] idx_lba;wire [8:0] idx_addr;
 wire sec_ready,sec_valid,sec_error;wire [7:0] buf_data;
 reg [31:0] cluster,left_bytes,size,sector_lba,hops;
 // Index outputs are stable before scan_done; separate lookup/comparison from control.
 reg entry_invalid;
 always @(posedge clk)entry_invalid<=size_entry<44 || cluster_entry<2 || cluster_entry>=max_cluster;
 reg [7:0] sec_in_cluster;reg [8:0] byte_addr;reg [1:0] fat_i;
 reg [31:0] fat_word;reg [31:0] cluster_base,cluster_delta,cluster_shifted;
 reg last_byte,file_empty;reg [7:0] parser_data_q;reg [31:0] hop_limit;
 always @(posedge clk)begin parser_data_q<=buf_data;hop_limit<=max_cluster-2;end
 always @(posedge clk)begin last_byte<=left_bytes==1;file_empty<=left_bytes==0;end
 always @(posedge clk)begin
  cluster_delta<=cluster-2;cluster_shifted<=cluster_delta<<shift;cluster_base<=data_lba+cluster_shifted;
 end
 wire scanning=state==SCAN || state==OPEN;
 wire stopping=cancel || state==DRAIN;
 wire req=!stopping && (scanning ? idx_req : state==REQ || state==FREQ);
 wire release_buf=stopping || (scanning ? idx_release : state==REL || state==FCHK);
 wire [8:0] address=scanning ? idx_addr :
    (state==FADDR || state==FCOPY) ? {cluster[6:0],2'b00}+fat_i : byte_addr;
 wire parser_ready,parser_done;wire [7:0] parser_error;
 wire [31:0] next_cluster={4'd0,fat_word[27:0]};
 reg chain_invalid;
 always @(posedge clk)chain_invalid<=next_cluster<2 || next_cluster>=max_cluster ||
  next_cluster>=32'h0ffffff0 || next_cluster==cluster || hops>=hop_limit;
 assign busy=state!=IDLE;
 assign cached_select=selected;
 generate if(USE_CACHED_INDEX)begin: shared_index
  assign scan_done=cached_done;assign scan_busy=0;assign scan_error=cached_error;
  assign present=cached_present;assign cluster_entry=cached_cluster;assign size_entry=cached_size;
  assign fat_lba=cached_fat_lba;assign data_lba=cached_data_lba;assign max_cluster=cached_max_cluster;
  assign spc=cached_spc;assign shift=cached_shift;
  assign idx_req=0;assign idx_release=0;assign idx_lba=0;assign idx_addr=0;
 end else begin: private_index
 museum_audio_fat_index idx(.clk(clk),.rst(index_rst),.scan_start(scan_pulse),
  .count(),.done(scan_done),.busy(scan_busy),.error(scan_error),.present_mask(present),
  .ent_raddr({3'd0,selected}),.ent_cluster(cluster_entry),.ent_size(size_entry),.ent_name(),
  .geo_fat_lba(fat_lba),.geo_data_lba(data_lba),.geo_spc(spc),.geo_shift(shift),.geo_max_cluster(max_cluster),
  .sec_req(idx_req),.sec_lba(idx_lba),.sec_ready(sec_ready),
  .sec_valid(sec_valid && scanning),.sec_error(sec_error && scanning),
  .buf_addr(idx_addr),.buf_data(buf_data),.sec_release(idx_release));
 end endgenerate
 // scan_start must occur after the index reset; delayed INIT pulse below.
 
 always @(posedge clk)if(rst)scan_pulse<=0;else scan_pulse<=state==INIT;
 museum_phase2_sd_sector sector(.clk(clk),.rst(rst),
  .req_valid(req),.req_lba(scanning ? idx_lba : sector_lba),.req_ready(sec_ready),
  .sector_valid(sec_valid),.sector_error(sec_error),.buf_release(release_buf),.buf_addr(address),.buf_data(buf_data),
  .rd_req_valid(rd_req_valid),.rd_lba(rd_lba),.rd_count(rd_count),.rd_req_ready(rd_req_ready),
  .rd_data(rd_data),.rd_valid(rd_valid),.rd_sector_commit(rd_sector_commit),.rd_done(rd_done),
  .rd_error(rd_error),.rd_resume(rd_resume));
 museum_wav_parser parser(.clk(clk),.rst(rst || stopping || state==INIT),.start(state==PRIME),.file_size(size),
  .in_data(parser_data_q),.in_valid(state==FEED && !stopping),.in_last(last_byte),.in_ready(parser_ready),
  .pcm_data(pcm_data),.pcm_valid(pcm_valid),.pcm_last(pcm_last),.pcm_ready(pcm_ready),
  .total_samples(total_samples),.done(parser_done),.error(parser_error));
 always @(posedge clk)begin
  if(rst)begin
   state<=IDLE;selected<=0;finished<=0;error<=0;cluster<=0;left_bytes<=0;size<=0;
   sector_lba<=0;sec_in_cluster<=0;byte_addr<=0;fat_i<=0;fat_word<=0;hops<=0;
  end else if(cancel && state!=IDLE && state!=DRAIN)state<=DRAIN;
  else case(state)
   IDLE:if(start)begin state<=INIT;selected<=exhibit;finished<=0;error<=0;end
   INIT:state<=SCAN;
   SCAN:if(scan_error!=0)begin error<=scan_error;state<=DRAIN;end
        else if(scan_done)state<=OPEN;
   OPEN:begin
    if(!present[selected])begin error<=8'h90;state<=DRAIN;end
    else if(entry_invalid)begin error<=8'h91;state<=DRAIN;end
    else begin size<=size_entry;left_bytes<=size_entry;cluster<=cluster_entry;
     sec_in_cluster<=0;hops<=0;state<=PRIME;end
   end
   PRIME:state<=BASE_WAIT0;
   BASE_WAIT0:state<=BASE_WAIT1;
   BASE_WAIT1:state<=NEXT;
   NEXT:begin sector_lba<=cluster_base+sec_in_cluster;state<=REQ;end
   REQ:if(sec_ready)state<=WAIT;
   WAIT:if(sec_error)begin error<=8'h92;state<=DRAIN;end
        else if(sec_valid)begin byte_addr<=0;state<=ADDR;end
   ADDR:state<=DATA_FETCH;
   DATA_FETCH:state<=FEED;
   FEED:begin
    if(parser_error!=0)begin error<=parser_error;state<=DRAIN;end
    else if(parser_done)state<=FLUSH;
    else if(parser_ready)begin
     left_bytes<=left_bytes-1'b1;
     if(byte_addr==511 || last_byte)state<=REL;
     else begin byte_addr<=byte_addr+1'b1;state<=ADDR;end
    end
   end
   REL:state<=ADV;
   ADV:begin
    if(parser_error!=0)begin error<=parser_error;state<=DRAIN;end
    else if(parser_done)state<=FLUSH;
    else if(file_empty)begin error<=8'h81;state<=DRAIN;end
    else if(sec_in_cluster+1<spc)begin sec_in_cluster<=sec_in_cluster+1'b1;state<=NEXT;end
    else begin sector_lba<=fat_lba+(cluster>>7);fat_i<=0;state<=FREQ;end
   end
   FREQ:if(sec_ready)state<=FWAIT;
   FWAIT:if(sec_error)begin error<=8'h92;state<=DRAIN;end
         else if(sec_valid)begin fat_i<=0;state<=FADDR;end
   FADDR:state<=FCOPY;
   FCOPY:begin
    fat_word<={buf_data,fat_word[31:8]};
    if(fat_i==3)state<=FCHK_WAIT;else begin fat_i<=fat_i+1'b1;state<=FADDR;end
   end
   FCHK_WAIT:state<=FCHK;
   FCHK:begin
    if(chain_invalid)begin error<=8'h93;state<=DRAIN;end
    else begin cluster<=next_cluster;sec_in_cluster<=0;hops<=hops+1'b1;state<=CLUSTER_WAIT;end
   end
   CLUSTER_WAIT:state<=BASE_WAIT0; // wait for registered cluster_base after following FAT
   FLUSH:if(!pcm_valid)begin finished<=1;state<=DRAIN;end
   DRAIN:if(sec_ready && !rd_req_valid)state<=IDLE;
   default:state<=IDLE;
  endcase
 end
endmodule

// Cache FAT sectors and coalesce the complete file into at most 256 physical runs.
// This keeps fragmented files valid while allowing long CMD18 transfers.
module fat32_extents #(parameter FILE_SECTORS=411750)(
 input clk,rst,mounted,input [31:0] fat_lba,data_lba,first_cluster,max_cluster,
 input [7:0] spc,input [2:0] cluster_shift,
 output reg read_req,output reg [31:0] read_lba,output reg [22:0] read_count,
 input [7:0] data,input valid,done,input resume_ok,
 output stream_valid,output [7:0] stream_data,output reg prepared,
 output reg [7:0] error
);
 localparam WAIT=0,LOOK=1,CACHE=2,ENTRY=3,CHECK=4,NEXT=5,
 END_CHECK=6,LOAD0=7,LOAD1=8,PLAY=9,HALT=10,PUT=11,START=12,ADDRESS0=13,ADDRESS1=14;
 reg [3:0] state;
 (* ram_style="bram_9k" *) reg [31:0] fat_cache[0:127];
 (* ram_style="bram_32k" *) reg [31:0] extent_lba[0:255];
 (* ram_style="bram_32k" *) reg [31:0] extent_len[0:255];
 reg [31:0] cache_tag,current,remaining,run_lba,run_len;
 reg cache_valid;
 reg [9:0] byte_index;
 reg [23:0] pack;
 reg [31:0] fat_q,lba_q,len_q,next_cluster;
 reg [8:0] extent_count;
 reg [7:0] extent_index;
 reg [31:0] here_lba,amount,cluster_offset,shifted_offset;
 reg contiguous;
 wire [31:0] cluster_lba=data_lba+((current-2)<<cluster_shift);
 wire [31:0] cluster_amount=remaining<spc ? remaining : spc;
 assign stream_valid=state==PLAY && valid;
 assign stream_data=data;
 always @(posedge clk) begin
  fat_q<=fat_cache[current[6:0]];
  lba_q<=extent_lba[extent_index];len_q<=extent_len[extent_index];
  if(valid && state==CACHE) begin
   pack<={pack[15:0],data};byte_index<=byte_index+1'b1;
   if(byte_index[1:0]==3) fat_cache[byte_index[8:2]]<={data,pack[7:0],pack[15:8],pack[23:16]};
  end
  if(rst) begin
   state<=WAIT;read_req<=0;read_lba<=0;read_count<=1;prepared<=0;error<=0;
   cache_tag<=0;cache_valid<=0;current<=0;remaining<=0;run_lba<=0;run_len<=0;
   byte_index<=0;pack<=0;extent_count<=0;extent_index<=0;next_cluster<=0;
   here_lba<=0;amount<=0;cluster_offset<=0;shifted_offset<=0;contiguous<=0;
  end else case(state)
   WAIT: if(mounted) begin
    current<=first_cluster;remaining<=FILE_SECTORS;run_lba<=0;run_len<=0;
    state<=ADDRESS0;
   end
   ADDRESS0: begin cluster_offset<=current-2;state<=ADDRESS1;end
   ADDRESS1: begin shifted_offset<=cluster_offset<<cluster_shift;state<=LOOK;end
   LOOK: begin
    here_lba<=data_lba+shifted_offset;amount<=cluster_amount;
    if(cache_valid && cache_tag==(current>>7)) state<=ENTRY;
    else begin
     read_req<=1;read_lba<=fat_lba+(current>>7);read_count<=1;
     byte_index<=0;state<=CACHE;
    end
   end
   CACHE: if(done) begin
    read_req<=0;
    if(byte_index!=512) begin error<=8'h31;state<=HALT;end
    else begin cache_valid<=1;cache_tag<=current>>7;state<=ENTRY;end
   end
   ENTRY: state<=CHECK;
   CHECK: begin
    next_cluster<={4'b0,fat_q[27:0]};contiguous<=here_lba==run_lba+run_len;state<=NEXT;
   end
   NEXT: begin
    if(run_len==0) begin run_lba<=here_lba;run_len<=amount;end
    else if(contiguous) run_len<=run_len+amount;
    else begin
     extent_lba[extent_count[7:0]]<=run_lba;
     extent_len[extent_count[7:0]]<=run_len;
     extent_count<=extent_count+1'b1;run_lba<=here_lba;run_len<=amount;
    end
    remaining<=remaining-amount;state<=END_CHECK;
   end
   END_CHECK: begin
    if(extent_count>=256) begin error<=8'h32;state<=HALT;end
    else if(remaining==0) begin
     if(next_cluster<32'h0ffffff8) begin error<=8'h33;state<=HALT;end
     else state<=PUT;
    end else if(next_cluster<2 || next_cluster>=max_cluster || next_cluster>=32'h0ffffff0) begin
     error<=8'h33;state<=HALT;
    end else begin current<=next_cluster;state<=ADDRESS0;end
   end
   PUT: begin
    extent_lba[extent_count[7:0]]<=run_lba;
    extent_len[extent_count[7:0]]<=run_len;
    extent_count<=extent_count+1'b1;extent_index<=0;prepared<=1;state<=LOAD0;
   end
   LOAD0: state<=LOAD1;
   LOAD1: begin read_lba<=lba_q;read_count<=len_q[22:0];state<=START;end
   START: if(resume_ok) begin read_req<=1;state<=PLAY;end
   PLAY: if(done) begin
    read_req<=0;
    if({1'b0,extent_index}+1==extent_count) extent_index<=0;
    else extent_index<=extent_index+1'b1;
    state<=LOAD0;
   end
   HALT: read_req<=0;
  endcase
 end
endmodule

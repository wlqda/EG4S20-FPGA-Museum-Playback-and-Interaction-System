`timescale 1ns/1ps
// Fast sector-level model: fragmented, contiguous and cross-cache FAT chains.
module gesture_fat_sd_model #(parameter MODE=0)(input wire clk,rst,req,
 input wire [31:0] lba,input wire [22:0] count,output reg valid,done,
 output reg [7:0] data,output reg transaction,output reg [31:0] transaction_lba,
 output reg [22:0] transaction_count);
 reg active,latched,pending_done;reg [31:0] saved_lba;integer index,limit;
 function [31:0] chain(input integer c);begin
  chain=32'h0fffffff;
  case(MODE)
   0:case(c)3:chain=5;5:chain=4;endcase
   1:case(c)3:chain=4;4:chain=5;endcase
   2:case(c)3:chain=130;130:chain=131;endcase
   3:if(c==3)chain=1;
   4:case(c)127:chain=128;128:chain=129;endcase
  endcase
 end endfunction
 function [7:0] byte_at(input [31:0] sector,input integer offset);
  reg [31:0] word;begin
   byte_at=0;
   if(sector==0)case(offset)
    12:byte_at=2;13:byte_at=1;14:byte_at=32;16:byte_at=2;
    34:byte_at=2;37:byte_at=2;44:byte_at=2;510:byte_at=8'h55;511:byte_at=8'haa;
   endcase
   else if(sector==32 || sector==33)begin word=chain((sector-32)*128+offset/4);byte_at=word>>((offset%4)*8);end
   else if(sector==1056)case(offset)
    0:byte_at="A";1:byte_at="V";2:byte_at="V";3:byte_at="I";4:byte_at="D";5:byte_at="E";6:byte_at="O";
    7:byte_at=" ";8:byte_at="B";9:byte_at="I";10:byte_at="N";11:byte_at=8'h20;26:byte_at=MODE==4 ? 127 : 3;29:byte_at=6;
   endcase
   else byte_at=sector+offset;
  end
 endfunction
 always @(posedge clk)begin
  valid<=0;done<=pending_done;pending_done<=0;transaction<=0;
  if(rst)begin active<=0;latched<=0;pending_done<=0;done<=0;saved_lba<=0;index<=0;limit<=0;data<=0;transaction_lba<=0;transaction_count<=0;end
  else begin
   if(!req)latched<=0;
   if(!active && !latched && req)begin
    active<=1;latched<=1;saved_lba<=lba;index<=0;limit<=count*512;
    transaction<=1;transaction_lba<=lba;transaction_count<=count;
   end else if(active)begin
    valid<=1;data<=byte_at(saved_lba+index/512,index%512);index<=index+1;
    if(index==limit-1)begin active<=0;pending_done<=1;end
   end
  end
 end
endmodule

module tb_camera_gesture_extents #(parameter MODE=0);
 reg clk=0;always #5 clk=~clk;reg rst=1;
 wire req,valid,done,transaction,prepared,stream_valid;wire [31:0] lba,transaction_lba;
 wire [22:0] count,transaction_count;wire [7:0] data,stream_data,error;
 integer streams=0,bytes=0,fat_reads=0;reg passed=0;
 fat32_extents #(.FILE_SECTORS(3)) dut(.clk(clk),.rst(rst),.mounted(!rst),
  .fat_lba(32'd32),.data_lba(32'd1056),.first_cluster(32'd3),.max_cluster(32'd130000),.spc(8'd1),.cluster_shift(3'd0),
  .read_req(req),.read_lba(lba),.read_count(count),.data(data),.valid(valid),.done(done),.resume_ok(1'b1),
  .stream_valid(stream_valid),.stream_data(stream_data),.prepared(prepared),.error(error));
 gesture_fat_sd_model #(.MODE(MODE)) sd(.clk(clk),.rst(rst),.req(req),.lba(lba),.count(count),
  .valid(valid),.done(done),.data(data),.transaction(transaction),.transaction_lba(transaction_lba),.transaction_count(transaction_count));
 function integer sector_at(input integer n);begin
  if(MODE==0)case(n%3)0:sector_at=1057;1:sector_at=1059;2:sector_at=1058;endcase
  else if(MODE==1)sector_at=1057+n%3;
  else sector_at=n%3==0 ? 1057 : 1183+n%3;
 end endfunction
 always @(negedge clk)if(!rst)begin
  if(transaction)begin
   if(!prepared)fat_reads=fat_reads+1;
   else begin
    if(MODE==0 && (transaction_lba!=sector_at(streams) || transaction_count!=1))$fatal(1,"Fragmented extent order");
    if(MODE==1 && (transaction_lba!=1057 || transaction_count!=3))$fatal(1,"Contiguous run not coalesced");
    if(MODE==2 && (transaction_lba!=(streams%2==0 ? 1057 : 1184) || transaction_count!=(streams%2==0 ? 1 : 2)))$fatal(1,"Cross-cache extent order");
    streams=streams+1;
   end
  end
  if(stream_valid)begin
   if(stream_data!=((sector_at(bytes/512)+bytes%512)&255))$fatal(1,"Extent data mismatch at byte %d",bytes);
   bytes=bytes+1;
  end
 end
 initial begin
  repeat(4)@(negedge clk);rst=0;
  if(MODE==3)begin wait(error!=0);if(error!=8'h33 || prepared)$fatal(1,"Invalid chain accepted");end
  else begin wait(bytes>=3072);if(error || fat_reads!=(MODE==2 ? 2 : 1))$fatal(1,"FAT cache or playback failed");end
  passed=1;$display("PASS gesture extents: mode=%d coalescing, cache hit/miss, replay, bytes and bad-chain rejection",MODE);$finish;
 end
 initial begin #500000;$fatal(1,"Extent watchdog state=%d error=%h prepared=%b bytes=%d current=%d",dut.state,error,prepared,bytes,dut.current);end
endmodule

module tb_camera_gesture_mount #(parameter MODE=0);
 reg clk=0;always #5 clk=~clk;reg rst=1;
 wire req,valid,done,transaction,mounted,sector_ready,stream_valid,sector_done;wire [31:0] lba,transaction_lba;
 wire [22:0] transaction_count;wire [7:0] data,stream_data,error;wire [15:0] unused;
 integer bytes=0;reg passed=0;
 museum_phase1_mount #(.EXPECTED_BYTES(1536)) dut(.clk(clk),.rst(rst),.sd_ready(1'b1),.sd_error(8'd0),
  .read_req(req),.read_lba(lba),.sd_data(data),.sd_valid(valid),.sd_done(done),.mounted(mounted),.error(error),
  .next_sector(sector_ready && bytes<2048),.sector_ready(sector_ready),.stream_data(stream_data),.stream_valid(stream_valid),.sector_done(sector_done),
  .file_size(),.debug_state(),.mount_fat_lba(),.mount_data_lba(),.mount_first_cluster(),.mount_max_cluster(),.mount_spc(),.mount_shift());
 gesture_fat_sd_model #(.MODE(MODE)) sd(.clk(clk),.rst(rst),.req(req),.lba(lba),.count(23'd1),
  .valid(valid),.done(done),.data(data),.transaction(transaction),.transaction_lba(transaction_lba),.transaction_count(transaction_count));
 function integer sector_at(input integer n);begin
  if(MODE==4)sector_at=1181+n%3;
  else case(n%3)0:sector_at=1057;1:sector_at=1059;2:sector_at=1058;endcase
 end endfunction
 // The current mount controller has a different pipeline and no archived
 // directory_active probe. Verify its public fragmented stream below instead.
 always @(negedge clk)if(!rst && stream_valid)begin
  if(stream_data!=((sector_at(bytes/512)+bytes%512)&255))$fatal(1,"Mounted file data mismatch byte %d",bytes);
  bytes=bytes+1;
 end
 initial begin
  repeat(4)@(negedge clk);rst=0;wait(bytes>=2048);
  if(error || !mounted)$fatal(1,"Mount, fragmented FAT or end-of-file replay failed");
  passed=1;$display("PASS gesture mount: real BPB/root parsing, fragmented sectors, exact file size, end-of-file replay");$finish;
 end
 initial begin #500000;$fatal(1,"Mount watchdog error=%h state=%d bytes=%d",error,dut.state,bytes);end
endmodule

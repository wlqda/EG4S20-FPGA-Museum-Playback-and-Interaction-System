`timescale 1ns/1ps
module tb_av_demux;
 reg clk=0,rst=1,valid=0,commit=0,bad=0,vr=1,ar=1;
 reg [7:0] data;
 always #5 clk=~clk;
 wire resume_ok,vvalid,avalid,vcommit,seal;
 wire [7:0] vd,ad,error;
 wire [1:0] bank,sbank;
 av_demux #(.VIDEO_SECTORS(2),.AUDIO_SECTORS(1)) dut(.clk(clk),.rst(rst),.data(data),.valid(valid),
  .sector_commit(commit),.stream_error(bad),.video_resume(vr),.audio_resume(ar),.resume_ok(resume_ok),
  .video_data(vd),.audio_data(ad),.video_valid(vvalid),.audio_valid(avalid),.video_commit(vcommit),
  .audio_seal(seal),.packet_bank(bank),.seal_bank(sbank),.error(error));
 integer video_bytes=0,audio_bytes=0,commits=0,seals=0;
 always @(posedge clk) begin
  if(vvalid)video_bytes=video_bytes+1;
  if(avalid)audio_bytes=audio_bytes+1;
  if(vcommit)commits=commits+1;
  if(seal)seals=seals+1;
 end
 task sector;
  integer i;
  begin
   for(i=0;i<512;i=i+1)begin @(negedge clk);valid=1;data=i;end
   @(negedge clk);valid=0;commit=1;
   @(negedge clk);commit=0;repeat(3)@(negedge clk);
  end
 endtask
 integer f;
 initial begin
  #100;@(negedge clk);rst=0;
  for(f=0;f<4;f=f+1) begin
   sector();sector();
   if(commits!=2*f+1 || seals!=f)$fatal(1,"Video prematurely sealed");
   vr=0;ar=1;if(!resume_ok)$fatal(1,"Audio blocked by full video");
   ar=0;#1;if(resume_ok)$fatal(1,"Audio resume missing");ar=1;sector();vr=1;
   if(commits!=2*f+2 || seals!=f+1 || sbank!=f%3 || bank!=(f+1)%3)$fatal(1,"Packet/bank commit mismatch");
  end
  if(video_bytes!=4096 || audio_bytes!=2048 || error!=0)$fatal(1,"Bad byte routing");
  sector();sector();bad=1;sector();
  if(seals!=4 || commits!=9)$fatal(1,"CRC failure published AV frame");
  rst=1;repeat(4)@(negedge clk);rst=0;bad=0;
  @(negedge clk);valid=1;@(negedge clk);valid=0;commit=1;
  @(negedge clk);commit=0;repeat(2)@(negedge clk);
  if(error!=8'h61)$fatal(1,"Bad sector length not detected");
  $display("PASS AV_DEMUX: CRC-gated packet, byte routing, audio backpressure, bank wrap, corrupt packet, short sector");$finish;
 end
endmodule

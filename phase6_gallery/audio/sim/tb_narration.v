`timescale 1ns/1ps
module tb_narration;
 parameter MBR_SLOT=-1;
 parameter CACHED=0;
 reg mclk=0,pclk=0,mrst=1,prst=1;
 always #5 mclk=~mclk;always #20 pclk=~pclk;
 reg start=0,stop=0,paused=0;reg [1:0] exhibit=0;
 wire ready,playing,busy,ended,sv,cv;wire [7:0] error,underflows;
 wire [23:0] sample;wire [31:0] consumed;
 wire req,resume;wire [31:0] lba;wire [22:0] count;
 wire aready,avalid,acommit,adone;wire [7:0] adata,aerror;wire hreq,hresume,image_done;wire [31:0] hlba;wire [22:0] hcount;
 reg image_traffic=1;integer image_reads=0;
 reg rready=1,rv=0,commit=0,rdone=0;reg [7:0] data=0,rerror=0;
 reg [31:0] active_lba;integer sdstate=0,off=0,waits=0;
 integer corrupt=-1,missing=-1,bad_format=0,extra_delay=0;
 reg [7:0] boot[0:511],fat[0:511],directory[0:511],wav[0:1255];
 integer expected_id=0,received=0,checks=0;reg check_pcm=0,passed=0;
 wire [1:0] cache_select;
 reg [3:0] cache_present;reg [31:0] cache_cluster,cache_size;integer cs,ci;
 always @*begin
  cache_present=0;cache_cluster=0;cache_size=0;
  for(cs=0;cs<4;cs=cs+1)begin
   ci=directory[cs*32+7]-8'd49;
   if(ci>=0 && ci<4 && cs!=missing && directory[cs*32]!=8'he5)begin
    cache_present[ci]=1;
    if(ci==cache_select)begin
     cache_cluster={4'd0,directory[cs*32+21][3:0],directory[cs*32+20],directory[cs*32+27],directory[cs*32+26]};
     cache_size={directory[cs*32+31],directory[cs*32+30],directory[cs*32+29],directory[cs*32+28]};
    end
   end
  end
 end
 museum_narration_player #(.PIXEL_HZ(480000),.SAMPLE_HZ(48000),.FIFO_ADDR(6),.USE_CACHED_INDEX(CACHED)) dut(
  .cached_done(1'b1),.cached_error(8'd0),.cached_present(cache_present),.cached_cluster(cache_cluster),.cached_size(cache_size),
  .cached_fat_lba(MBR_SLOT>=0 ? 32'd2049 : 32'd1),.cached_data_lba(MBR_SLOT>=0 ? 32'd2561 : 32'd513),
  .cached_max_cluster(32'd69489),.cached_spc(8'd1),.cached_shift(3'd0),.cached_select(cache_select),
  .mem_clk(mclk),.mem_rst(mrst),.pixel_clk(pclk),.pixel_rst(prst),
  .cmd_start(start),.cmd_stop(stop),.exhibit(exhibit),.paused(paused),.cmd_ready(ready),
  .playing(playing),.busy(busy),.ended(ended),.error(error),
  .sample_valid(sv),.content_valid(cv),.sample_data(sample),.consumed_samples(consumed),.underflows(underflows),
  .rd_req_valid(req),.rd_lba(lba),.rd_count(count),.rd_req_ready(aready),.rd_data(adata),
  .rd_valid(avalid),.rd_sector_commit(acommit),.rd_done(adone),.rd_error(aerror),.rd_resume(resume));

 museum_sd_service arbiter(.clk(mclk),.rst(mrst),
  .a_req(image_traffic),.a_lba(32'd513),.a_count(23'd1),.a_resume(1'b1),
  .a_ready(),.a_data(),.a_valid(),.a_commit(),.a_done(image_done),.a_error(),
  .b_req(req),.b_lba(lba),.b_count(count),.b_resume(resume),
  .b_ready(aready),.b_data(adata),.b_valid(avalid),.b_commit(acommit),.b_done(adone),.b_error(aerror),
  .host_req(hreq),.host_lba(hlba),.host_count(hcount),.host_resume(hresume),
  .host_ready(rready),.host_data(data),.host_valid(rv),.host_commit(commit),.host_done(rdone),.host_error(rerror));
 always @(posedge mclk)if(image_done)image_reads<=image_reads+1;
 function [15:0] value;input integer id,n;begin value=n*37+id*1000-16000;end endfunction
 function [7:0] disk;input integer sector,index;
  integer cl,id,rel,n,k;reg [15:0] v;
  begin
   if(MBR_SLOT>=0 && sector==0)begin
    disk=0;
    if(index==450+MBR_SLOT*16)disk=8'h0c;
    if(index==455+MBR_SLOT*16)disk=8'h08;
    if(index==510)disk=8'h55;
    if(index==511)disk=8'haa;
   end else begin
   if(MBR_SLOT>=0)sector=sector-2048;
   disk=0;
   if(sector==0)disk=boot[index];
   else if(sector==1)disk=fat[index];
   else if(sector==513)begin
    disk=directory[index];
    if(index/32==missing && index%32==0)disk=8'he5;
   end else begin
    cl=sector-513+2;id=(cl-3)/8;rel=cl-(3+id*8);
    if(cl>=3 && id<4 && rel>=0 && rel<=4 && rel%2==0)begin
     n=(rel/2)*512+index;
     if(n<56)begin disk=wav[n];if(bad_format && n==46)disk=8;end
     else if(n<1256)begin k=(n-56)/2;v=value(id,k);disk=(n%2) ? v[15:8] : v[7:0];end
    end
   end
   end
  end
 endfunction
 always @(posedge mclk)begin
  rv<=0;commit<=0;rdone<=0;
  if(mrst)begin sdstate<=0;rready<=1;rerror<=0;end
  else case(sdstate)
   0:if(hreq && rready)begin
    if(hcount!=1)$fatal(1,"unbounded read count");
    active_lba<=hlba;off<=0;waits<=7+extra_delay;rready<=0;rerror<=0;sdstate<=1;
   end
   1:if(waits!=0)waits<=waits-1;else if(hresume)sdstate<=2;
   2:begin
    data<=disk(active_lba,off);rv<=1;
    if(off==511)sdstate<=3;else off<=off+1;
   end
   3:begin if(active_lba==(MBR_SLOT>=0 ? corrupt+2048 : corrupt))rerror<=8'h10;else commit<=1;sdstate<=4;end
   4:begin rdone<=1;sdstate<=5;end
   5:begin sdstate<=0;rready<=1;rerror<=0;end
  endcase
 end
 always @(negedge pclk)if(check_pcm && cv)begin
  if(sample!={value(expected_id,received),8'd0})$fatal(1,"PCM mismatch id=%0d sample=%0d got=%h",expected_id,received,sample);
  received=received+1;
 end
 task cycles;input integer n;begin repeat(n)@(negedge pclk);end endtask
 task launch;input integer id;begin
  wait(ready);@(negedge pclk);exhibit=id;start=1;cycles(1);start=0;
 end endtask
 task halt;begin wait(ready);@(negedge pclk);stop=1;cycles(1);stop=0;wait(ready);cycles(10);end endtask
 task run_track;input integer id;begin $display("RUN track %0d checks=%0d",id,checks);
  halt;expected_id=id;received=0;check_pcm=1;launch(id);
  wait(ended || error!=0);cycles(2);
  if(error!=0 || received!=600 || consumed!=600)$fatal(1,"track %0d incomplete err=%h received=%0d",id,error,received);
  check_pcm=0;checks=checks+1;
 end endtask
 integer i,j,k,id,cl;reg [31:0] word;
 initial begin
  for(i=0;i<512;i=i+1)begin boot[i]=0;fat[i]=0;directory[i]=0;end
  for(i=0;i<1256;i=i+1)wav[i]=0;
  boot[11]=0;boot[12]=2;boot[13]=1;boot[14]=1;boot[16]=1;
  word=70000;for(i=0;i<4;i=i+1)boot[32+i]=(word>>(8*i));
  boot[36]=0;boot[37]=2;boot[44]=2;boot[510]=8'h55;boot[511]=8'haa;
  // shuffled root entries: ID 2,0,3,1
  for(j=0;j<4;j=j+1)begin
   case(j)0:id=2;1:id=0;2:id=3;3:id=1;endcase
   k=j*32;directory[k]="A";directory[k+1]="U";directory[k+2]="D";
   for(i=3;i<7;i=i+1)directory[k+i]="0";
   directory[k+7]="1"+id;directory[k+8]="W";directory[k+9]="A";directory[k+10]="V";
   directory[k+11]=8'h20;directory[k+26]=3+id*8;
   directory[k+28]=8'he8;directory[k+29]=4; // 1256
   for(i=0;i<3;i=i+1)begin
    cl=3+id*8+2*i;word=i==2 ? 32'h0fffffff : cl+2;
    for(k=0;k<4;k=k+1)fat[cl*4+k]=word>>(8*k);
   end
  end
  {wav[3],wav[2],wav[1],wav[0]}=32'h46464952;
  word=1248;for(i=0;i<4;i=i+1)wav[4+i]=word>>(8*i);
  {wav[11],wav[10],wav[9],wav[8]}=32'h45564157;
  {wav[15],wav[14],wav[13],wav[12]}=32'h4b4e554a;wav[16]=3; // odd JUNK
  {wav[27],wav[26],wav[25],wav[24]}=32'h20746d66;wav[28]=16;
  wav[32]=1;wav[34]=1;word=48000;for(i=0;i<4;i=i+1)wav[36+i]=word>>(8*i);
  word=96000;for(i=0;i<4;i=i+1)wav[40+i]=word>>(8*i);
  wav[44]=2;wav[46]=16;
  {wav[51],wav[50],wav[49],wav[48]}=32'h61746164;wav[52]=8'hb0;wav[53]=4;
  cycles(5);mrst=0;prst=0;cycles(5);
  for(j=0;j<4;j=j+1)run_track(j);
  halt;expected_id=0;received=0;check_pcm=1;launch(0);wait(received>=40);
  @(negedge pclk);paused=1;cycles(2);k=received;cycles(100);
  if(received!=k || sample!=0)$fatal(1,"pause advanced or nonzero");
  paused=0;wait(ended);cycles(2);if(received!=600)$fatal(1,"resume lost samples");
  check_pcm=0;checks=checks+1;
  // Switch while an SD transaction is in flight; stale bytes must never enter new FIFO.
  halt;launch(0);wait(sdstate==2 && arbiter.owner);halt;run_track(3);checks=checks+1;
  halt;corrupt=514;launch(0);wait(error!=0);
  if(consumed!=0)$fatal(1,"uncommitted sector leaked");halt;corrupt=-1;checks=checks+1;
  missing=1;launch(0);wait(error!=0);if(error!=8'h90)$fatal(1,"missing file error");halt;missing=-1;checks=checks+1;
  bad_format=1;launch(1);wait(error!=0);if(error!=8'h82 || consumed!=0)$fatal(1,"format rejection");halt;bad_format=0;checks=checks+1;
  run_track(2);
  halt;expected_id=0;received=0;check_pcm=1;launch(0);wait(received>=80);
  extra_delay=10000;wait(underflows!=0);extra_delay=0;
  wait(ended);cycles(2);if(received!=600)$fatal(1,"underflow lost content");
  check_pcm=0;checks=checks+1;

  // A new start without an intervening stop must drain old transactions too.
  halt;launch(0);wait(consumed>=40);launch(3);
  expected_id=3;received=0;check_pcm=1;
  wait(ended || error!=0);cycles(2);
  if(error!=0 || received!=600)$fatal(1,"direct switch stale content");
  check_pcm=0;checks=checks+1;
  // PCM data length must be even; leave RIFF padding valid so error is format-specific.
  halt;wav[52]=8'haf;launch(0);wait(error!=0);
  if(error!=8'h83 || consumed!=0)$fatal(1,"odd PCM length not rejected");
  halt;wav[52]=8'hb0;checks=checks+1;
  // Directory length shorter than the RIFF header advertises.
  directory[60]=100;directory[61]=0;launch(0);wait(error!=0);
  if(error!=8'h81 || consumed!=0)$fatal(1,"truncated WAV not rejected");
  halt;directory[60]=8'he8;directory[61]=4;checks=checks+1;
  // Self-referential FAT cluster is detected before a second copy of PCM is read.
  fat[12]=3;launch(0);wait(error!=0);
  if(error!=8'h93)$fatal(1,"FAT self-loop not rejected");
  halt;fat[12]=5;checks=checks+1;
  if(image_reads<10)$fatal(1,"image client starved");
  passed=1;$display("PASS narration: %0d checks, four IDs, fragmented FAT, odd chunks, tail, FIFO backpressure, pause, drain, CRC, missing, format, recovery, direct switch, odd length, truncation, bad FAT",checks);$finish;
 end
 always @(posedge mclk)if(CACHED && req && aready && (lba==0 || lba==513 || lba==2048 || lba==2561))
  $fatal(1,"cached reader rescanned boot/root");
 initial begin #5000000;$fatal(1,"watchdog checks=%d reader=%d err=%h",checks,dut.reader.state,error);end
endmodule

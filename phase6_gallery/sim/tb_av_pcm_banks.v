`timescale 1ns/1ps
module tb_av_pcm_banks;
 reg mclk=0,pclk=0,rst=1;
 always #5 mclk=~mclk;always #20 pclk=~pclk;
 reg [7:0] data=0;reg valid=0,seal=0,started=0,paused=0;
 reg [1:0] bank=0;wire can_write;wire [7:0] error,underflows;
 wire sv,due;wire [1:0] due_bank;wire [23:0] left,right;
 reg passed=0,checking=0,pause_at_sample;
 integer got=0,b,n,j,before_pause;
 reg [31:0] word;
 museum_phase1_audio #(.PIXEL_HZ(480000),.SAMPLE_HZ(48000)) dut(
  .mem_clk(mclk),.mem_rst(rst),.data(data),.valid(valid),.seal(seal),
  .packet_bank(bank),.seal_bank(bank),.stream_error(1'b0),.can_write(can_write),.error(error),
  .pixel_clk(pclk),.pixel_rst(rst),.video_started(started),.paused(paused),
  .sample_valid(sv),.left_data(left),.right_data(right),.due_toggle(due),.due_bank(due_bank),.underflows(underflows));
 always @(posedge pclk)pause_at_sample<=paused;
 always @(negedge pclk)if(checking && sv)begin
  if(pause_at_sample)begin
   if(left!==0 || right!==0)$fatal(1,"pause not silent");
  end else begin
   if(left!=={16'(got+1),8'd0} || right!=={16'(16'h9000+got),8'd0})
    $fatal(1,"AV PCM mismatch sample=%0d left=%h right=%h",got,left,right);
   got=got+1;
  end
 end
 initial begin
  repeat(4)@(negedge mclk);rst=0;
  for(b=0;b<3;b=b+1)begin
   bank=b;
   for(n=0;n<1920;n=n+1)begin
    word={16'(16'h9000+b*1920+n),16'(b*1920+n+1)};
    for(j=0;j<4;j=j+1)begin
     @(negedge mclk);valid=1;data=word>>(j*8);
     if(!can_write)$fatal(1,"bank rejected before seal");
    end
   end
   @(negedge mclk);valid=0;seal=1;
   @(negedge mclk);seal=0;
  end
  repeat(5)@(negedge pclk);#1;started=1;checking=1;
  wait(got==64);@(negedge pclk);#1;paused=1;before_pause=got;
  repeat(100)@(negedge pclk);
  if(got!=before_pause)$fatal(1,"pause advanced content");
  #1;paused=0;
  wait(got==5760);checking=0;
  repeat(4)@(negedge pclk);
  if(error!=0 || underflows!=0 || dut.ready_banks!=0)$fatal(1,"bank lifecycle error");
  passed=1;$display("PASS AV PCM banks: 5760 stereo samples, three sealed banks, pause/resume, no underflow");$finish;
 end
 initial begin #10000000;$fatal(1,"timeout got=%0d",got);end
endmodule

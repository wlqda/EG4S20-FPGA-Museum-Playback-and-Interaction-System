`timescale 1ns/1ps
module tb_pcm_bank_mapping;
 reg mem_clk=0,pixel_clk=0;always #5 mem_clk=~mem_clk;always #20 pixel_clk=~pixel_clk;
 reg mr=1,pr=1,valid=0,seal=0,start=0;reg [7:0] data=0;reg [1:0] bank=0;
 wire can_write,sv;wire [7:0] error,underflows;wire [23:0] left_data,right_data;wire due;wire [1:0] due_bank;
 museum_phase1_audio #(.PIXEL_HZ(480000),.SAMPLE_HZ(48000)) dut(.mem_clk(mem_clk),.mem_rst(mr),.data(data),.valid(valid),.seal(seal),
 .packet_bank(bank),.seal_bank(bank),.stream_error(1'b0),.can_write(can_write),.error(error),.pixel_clk(pixel_clk),.pixel_rst(pr),
 .video_started(start),.paused(1'b0),.sample_valid(sv),.left_data(left_data),.right_data(right_data),
 .due_toggle(due),.due_bank(due_bank),.underflows(underflows));
 function [31:0] pattern;input integer b,i;reg [15:0] l,r;begin
  l=16'h1000+b*2048+i;r=16'h9000+b*2048+i;pattern={r,l};
 end endfunction
 integer b,i,j,received=0;reg checking=0,passed=0;reg [31:0] word,expected;
 always @(posedge pixel_clk)begin
  #1;if(checking && sv)begin
   expected=pattern(received/1920,received%1920);
   if({right_data[23:8],left_data[23:8]}!==expected)$fatal(1,"PCM order/data mismatch at %0d got %h/%h expected %h",received,right_data,left_data,expected);
   if(left_data[7:0]!=0 || right_data[7:0]!=0)$fatal(1,"PCM scaling bits changed");
   received=received+1;
   if(received==5760)begin
    if(error || underflows)$fatal(1,"PCM error/underflow");
    passed=1;$display("PASS PCM RAM mapping: all 5760 stereo words, bank0/1/2, boundaries1023/1024 and final1919, no underflow");$finish;
   end
  end
 end
 initial begin
  repeat(5)@(negedge mem_clk);mr=0;repeat(3)@(negedge pixel_clk);pr=0;
  for(b=0;b<3;b=b+1)begin
   bank=b;
   for(i=0;i<1920;i=i+1)begin
    word=pattern(b,i);
    for(j=0;j<4;j=j+1)begin
     @(negedge mem_clk);if(!can_write)$fatal(1,"unexpected bank backpressure");valid=1;data=word>>(j*8);
    end
   end
   @(negedge mem_clk);valid=0;seal=1;@(negedge mem_clk);seal=0;
  end
  repeat(20)@(negedge pixel_clk);
  while(dut.phase!=0)@(negedge pixel_clk);
  start=1;@(negedge pixel_clk);start=0;checking=1;
 end
 initial begin #4000000;$fatal(1,"PCM mapping watchdog received=%0d",received);end
endmodule

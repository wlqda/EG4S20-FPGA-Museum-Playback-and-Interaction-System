`timescale 1ns/1ps
module tb_real_wav;
 reg clk=0,rst=1,start=0;always #5 clk=~clk;
 reg [31:0] file_size=0;reg [7:0] data=0;reg valid=0,last=0;wire ready;
 wire [15:0] pcm;wire pv,pl,done;wire [7:0] error;wire [31:0] total;
 reg [15:0] lfsr=16'hcafe;wire accept=lfsr[0] || lfsr[3];
 always @(posedge clk)lfsr<={lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
 reg [7:0] bytes[0:65535];reg [15:0] expected[0:16383];reg [31:0] sizes[0:3];
 integer id=0,n=0,i;reg passed=0;
 museum_wav_parser dut(.clk(clk),.rst(rst),.start(start),.file_size(file_size),
  .in_data(data),.in_valid(valid),.in_last(last),.in_ready(ready),
  .pcm_data(pcm),.pcm_valid(pv),.pcm_last(pl),.pcm_ready(accept),.total_samples(total),.done(done),.error(error));
 always @(posedge clk)if(!rst && !start && pv && accept)begin
  if(pcm!==expected[id*4096+n] || pl!==(n==4095))$fatal(1,"real WAV %0d sample %0d mismatch",id,n);
  n=n+1;
 end
 initial begin
  $readmemh("real_wav_input.hex",bytes);$readmemh("real_wav_expected.hex",expected);$readmemh("real_wav_sizes.hex",sizes);
  repeat(3)@(negedge clk);rst=0;
  for(id=0;id<4;id=id+1)begin
   file_size=sizes[id];start=1;n=0;@(negedge clk);start=0;
   for(i=0;i<sizes[id];i=i+1)begin
    valid=1;data=bytes[id*16384+i];last=i==sizes[id]-1;
    @(posedge clk);while(!ready)@(posedge clk);
    @(negedge clk);
   end
   valid=0;repeat(5)@(negedge clk);
   if(error!=0 || !done || n!=4096 || total!=4096)$fatal(1,"real WAV decode incomplete");
  end
  passed=1;$display("PASS real WAV: four original SAPI chunk layouts, 16384 exact PCM samples with random backpressure");$finish;
 end
 initial begin #3000000;$fatal(1,"watchdog");end
endmodule

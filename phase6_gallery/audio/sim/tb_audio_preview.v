`timescale 1ns/1ps
module tb_audio_preview;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [9:0] x=0,y=0;reg [23:0] base=0,sample=0;reg sv=0;
 wire [23:0] rgb,wave_rgb;reg [23:0] bg[0:307199],samples[0:1535];
 integer i,xx,yy,fd;reg passed=0;
 museum_audio_waveform dut(.clk(clk),.rst(rst),.x(x),.y(y),.active(1'b1),
  .base_rgb(base),.enabled(1'b1),.paused(1'b0),.loading(1'b0),.ended(1'b0),.error(8'd0),
  .sample_valid(sv),.sample_data(sample),.clear(1'b0),.out_rgb(wave_rgb));
 museum_floating_clock clock_overlay(.clk(clk),.rst(rst),.enabled(1'b1),.x(x),.y(y),.active(1'b1),.base_rgb(wave_rgb),.out_rgb(rgb));
 initial begin
  $readmemh("audio_background.hex",bg);$readmemh("wave_samples.hex",samples);
  repeat(3)@(negedge clk);rst=0;
  for(i=0;i<1536;i=i+1)begin sv=1;sample=samples[i];@(negedge clk);end
  sv=0;x=0;y=480;@(negedge clk);
  fd=$fopen("audio_preview.ppm","w");$fwrite(fd,"P3\n640 480\n255\n");
  for(yy=0;yy<480;yy=yy+1)begin
   for(xx=0;xx<640;xx=xx+1)begin
    x=xx;y=yy;base=bg[yy*640+xx];
    @(posedge clk);#1;$fwrite(fd,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
    @(negedge clk);
   end
  end
  $fclose(fd);passed=1;$display("PASS audio RTL preview");$finish;
 end
endmodule

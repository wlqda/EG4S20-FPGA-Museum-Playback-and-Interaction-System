`timescale 1ns/1ps
module tb_bmp_skip_boundary;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,start=0,valid=0,last=0,ready=1;
 reg [7:0] data=0;
 wire accept,hdr,pv,done,abort;wire [7:0] error;
 wire [15:0] iw,ih;wire bu;wire [18:0] addr;wire [23:0] rgb;
 integer passed=0,seen=0,cycle=0,w,h,off,stride,n,expected,xx,yy,j,k,t,polarity;
 reg [7:0] bytes[0:4095];
 museum_phase2_bmp_parser dut(.clk(clk),.rst(rst),.start(start),.in_data(data),
  .in_valid(valid),.in_ready(accept),.in_last(last),.in_error(1'b0),.hdr_valid(hdr),
  .img_width(iw),.img_height(ih),.bottom_up(bu),.pixel_valid(pv),.pixel_ready(ready),
  .pixel_addr(addr),.pixel_rgb(rgb),.error(error),.done(done),.abort(abort));
 task put32(input integer a,input integer v);
  begin bytes[a]=v;bytes[a+1]=v>>8;bytes[a+2]=v>>16;bytes[a+3]=v>>24;end
 endtask
 always @(posedge clk)begin
  cycle=cycle+1;
  if(!rst && pv && ready)begin
   xx=seen%w;yy=seen/w;
   if(addr!==((polarity ? yy : h-1-yy)*640+xx) ||
      rgb!=={8'(xx+11),8'(yy+31),8'(xx+yy+71)})$fatal(1,"pixel boundary mismatch %d",seen);
   seen=seen+1;
  end
 end
 initial begin
  for(polarity=0;polarity<2;polarity=polarity+1)
   for(w=1;w<=7;w=w+1)for(k=0;k<3;k=k+1)begin
    h=3;off=k==0 ? 54 : k==1 ? 70 : 256;stride=((w*3+3)/4)*4;n=off+stride*h;
    for(j=0;j<4096;j=j+1)bytes[j]=0;
    bytes[0]="B";bytes[1]="M";put32(2,n);put32(10,off);put32(14,40);
    put32(18,w);put32(22,polarity ? -h : h);bytes[26]=1;bytes[28]=24;
    for(j=0;j<h;j=j+1)for(t=0;t<w;t=t+1)begin
     bytes[off+j*stride+t*3]=t+j+71;
     bytes[off+j*stride+t*3+1]=j+31;bytes[off+j*stride+t*3+2]=t+11;
    end
    @(negedge clk);rst=1;valid=0;repeat(3)@(negedge clk);rst=0;seen=0;
    for(j=0;j<n;j=j+1)begin
     data=bytes[j];last=j==n-1;valid=1;
     @(posedge clk);while(!accept)begin @(negedge clk);ready=cycle%4!=0;@(posedge clk);end
     @(negedge clk);valid=0;ready=cycle%4!=0;
     if(j%5==0)@(negedge clk);
    end
    ready=1;repeat(12)@(negedge clk);
    if(error || !done || seen!=w*h || iw!=w || ih!=h)$fatal(1,"BMP failed %d %d %d %h",w,off,seen,error);
   end
  passed=1;$display("PASS BMP skip boundaries: 42 images, top-down/bottom-up, padded rows, 54/70/256 offsets and backpressure");$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule

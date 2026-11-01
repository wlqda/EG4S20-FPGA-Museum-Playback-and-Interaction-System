`timescale 1ns/1ps
module tb_v3_previews;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,active=0,collect=0,sv=0;reg [9:0] x=0,y=0;
 reg [23:0] bg[0:307199],samples[0:1535],base=0,sample=0;
 reg [3:0] page=0,photo=0;reg [1:0] focus=0;
 reg [9:0] render_x=0,render_y=0,wave_x=0,wave_y=0,clock_x=0,clock_y=0;
 reg render_de=0,gui_de=0,gui_de2=0;
 wire [23:0] gui_rgb,wave_rgb,rgb;
 always @(posedge clk)begin
  render_x<=x;render_y<=y;wave_x<=render_x;wave_y<=render_y;clock_x<=wave_x;clock_y<=wave_y;
  render_de<=active;gui_de<=render_de;gui_de2<=gui_de;
 end
 museum_phase6_render renderer(.clk(clk),.rst(rst),.x(x),.y(y),.active(active),.base_rgb(base),.page(page),.focus(focus),
 .photo_index(photo),.zoom(2'd0),.fade_level(5'd16),.gesture_enabled(1'b0),.editing(1'b0),.autoplay(1'b1),.interval_seconds(6'd8),
 .volume(9'd256),.brightness(9'd256),.image_mode(1'b1),.playing(page==4),.paused(1'b0),.screen_visible(1'b1),.frame_valid(1'b1),.media_error(8'd0),.out_rgb(gui_rgb));
 museum_audio_waveform waveform(.clk(clk),.rst(rst),.x(wave_x),.y(wave_y),.active(gui_de),.base_rgb(gui_rgb),.enabled(page==4),
 .paused(1'b0),.loading(1'b0),.ended(1'b0),.error(8'd0),.sample_valid(sv),.sample_data(sample),.clear(1'b0),.out_rgb(wave_rgb));
 museum_floating_clock floating_clock(.clk(clk),.rst(rst),.enabled(1'b1),.x(clock_x),.y(clock_y),.active(gui_de2),.base_rgb(wave_rgb),.out_rgb(rgb));
 string basename;
 integer fd,count=0,idx,i,xx,yy;reg passed=0;
 always @(posedge clk)begin
  #1;
  if(collect && gui_de2)begin
   if(clock_x!==count%640 || clock_y!==count/640)$fatal(1,"pipeline alignment %0d xy%0d,%0d count%0d",idx,clock_x,clock_y,count);
   if(^rgb===1'bx)$fatal(1,"unknown output pixel");
   $fwrite(fd,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);count=count+1;
  end
 end
 initial begin
  for(idx=5;idx<=29;idx=idx+1)begin
   rst=1;active=0;collect=0;sv=0;x=0;y=0;repeat(5)@(negedge clk);
   page=idx==5 ? 0 : idx==6 ? 1 : idx<=10 ? 2 : idx<=14 ? 4 : idx==15 ? 5 : idx==16 ? 3 : 7;
   photo=idx>=17 ? idx-17 : 0;
   basename=idx<10 ? $sformatf("v3_preview/IMG0000%0d",idx) : $sformatf("v3_preview/IMG000%0d",idx);
   $readmemh({basename,".hex"},bg);
   rst=0;repeat(4)@(negedge clk);
   // Publish clock enable once in blanking before capturing the active frame.
   y=480;for(i=0;i<8;i=i+1)begin x=i;@(negedge clk);end
   x=0;y=0;repeat(4)@(negedge clk);
   if(page==4)begin
    $readmemh($sformatf("v3_preview/wave_%0d.hex",idx-11),samples);
    for(i=0;i<1536;i=i+1)begin sv=1;sample=samples[i];@(negedge clk);end
    sv=0;y=480;
    for(i=0;i<8;i=i+1)begin x=i;@(negedge clk);end
   end
   fd=$fopen({basename,".ppm"},"w");$fwrite(fd,"P3\n640 480\n255\n");count=0;collect=1;
   for(yy=0;yy<525;yy=yy+1)for(xx=0;xx<800;xx=xx+1)begin
    x=xx;y=yy;active=xx<640 && yy<480;base=active ? bg[yy*640+xx] : 0;@(negedge clk);
   end
   active=0;repeat(5)@(negedge clk);collect=0;$fclose(fd);
   if(count!=307200)$fatal(1,"pixel count %0d =%0d",idx,count);
   $display("PASS V3 page %0d, 307200 aligned pixels",idx);
  end
  passed=1;$display("PASS V3 previews: 25 pages, 7680000 aligned RGB pixels");$finish;
 end
 initial begin #200000000;$fatal(1,"V3 preview watchdog");end
endmodule

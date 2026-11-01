`timescale 1ns/1ps
module tb_floating_clock;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,active=0,enabled=1;reg [9:0] x=0,y=0;
 wire [23:0] rgb;reg passed=0;
 museum_floating_clock #(.CLOCK_HZ(8),.MOVE_FRAMES(1),.INITIAL_HOUR(23),.INITIAL_MINUTE(59),.INITIAL_SECOND(59)) dut(
 .clk(clk),.rst(rst),.enabled(enabled),.x(x),.y(y),.active(active),.base_rgb(24'h123456),.out_rgb(rgb));
 reg day_passed=0;integer day_second;wire [23:0] day_rgb;
 museum_floating_clock #(.CLOCK_HZ(1),.INITIAL_HOUR(0),.INITIAL_MINUTE(0),.INITIAL_SECOND(0)) day_counter(
 .clk(clk),.rst(rst),.enabled(1'b1),.x(10'd0),.y(10'd0),.active(1'b0),.base_rgb(24'd0),.out_rgb(day_rgb));
 initial begin
  wait(!rst);
  for(day_second=1;day_second<=86400;day_second=day_second+1)begin
   @(posedge clk);#1;
   if(day_counter.seconds!==day_second%60 || day_counter.minutes!==(day_second/60)%60 || day_counter.hours!==(day_second/3600)%24)
    $fatal(1,"BCD full-day mismatch at %0d",day_second);
  end
  day_passed=1;
 end
 task step;begin @(posedge clk);#1;end endtask
 task frame;begin @(negedge clk);x=0;y=480;step;@(negedge clk);y=0;step;end endtask
 integer i,j,f,white,bg,border,fd,before_seconds;reg [9:0] px,py;
 initial begin
  step;@(negedge clk);rst=0;
  repeat(8)step;
  if(dut.hours!=0 || dut.minutes!=0 || dut.seconds!=0)$fatal(1,"midnight rollover");
  if(dut.show_hours!=23 || dut.show_seconds!=59)$fatal(1,"snapshot changed outside blanking");
  frame;
  if(dut.show_hours!=0 || dut.show_seconds!=0)$fatal(1,"snapshot not committed");
  for(f=0;f<2200;f=f+1)begin
   px=dut.pos_x;py=dut.pos_y;frame;
   if(dut.pos_x>496 || dut.pos_y>448)$fatal(1,"out of screen");
   if(!((dut.pos_x==px+1)||(px==dut.pos_x+1)))$fatal(1,"horizontal discontinuity");
   if(!((dut.pos_y==py+1)||(py==dut.pos_y+1)))$fatal(1,"vertical discontinuity");
  end
  px=dut.pos_x;py=dut.pos_y;white=0;bg=0;border=0;
  fd=$fopen("floating_clock.ppm","w");$fwrite(fd,"P3\n640 480\n255\n");
  @(negedge clk);active=1;
  for(j=0;j<480;j=j+1)for(i=0;i<640;i=i+1)begin
   x=i;y=j;#1;
   if(i<px || i>=px+144 || j<py || j>=py+32)begin
    if(rgb!==24'h123456)$fatal(1,"background mismatch");bg=bg+1;
   end else begin
    if(rgb==24'h000000)white=white+1;
    if(rgb!==24'h000000 && rgb!==24'h123456)$fatal(1,"clock transparency/color");
   end
   $fwrite(fd,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
   step;@(negedge clk);
   if(dut.pos_x!=px || dut.pos_y!=py)$fatal(1,"position tearing");
  end
  $fclose(fd);
  if(bg!=302592 || white<100 || white>=2000)$fatal(1,"glyph or frame geometry");
  enabled=0;#1;if(dut.visible!==1)$fatal(1,"visibility changed mid-frame");
  frame;active=1;
  if(dut.visible!==0)$fatal(1,"SW1 off not committed in blanking");
  before_seconds=dut.seconds;repeat(16)step;
  if(dut.seconds!==(before_seconds+2)%60)$fatal(1,"hidden clock stopped counting");
  for(j=0;j<32;j=j+1)for(i=0;i<144;i=i+1)begin
   x=dut.pos_x+i;y=dut.pos_y+j;#1;
   if(rgb!==24'h123456)$fatal(1,"hidden clock changed underlying pixel");
  end
  enabled=1;#1;if(dut.visible!==0)$fatal(1,"enable changed mid-frame");
  frame;if(dut.visible!==1)$fatal(1,"SW1 on not committed");
  active=0;#1;if(rgb!==24'h123456)$fatal(1,"blanking passthrough");
  if(!day_passed)$fatal(1,"full-day check incomplete");
  passed=1;$display("PASS floating clock: midnight, snapshot, 2200 motion frames, 307200 pixels, blanking");$finish;
 end
 initial begin #20000000;$fatal(1,"timeout");end
endmodule

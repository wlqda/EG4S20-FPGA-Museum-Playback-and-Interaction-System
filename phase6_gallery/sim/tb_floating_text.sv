`timescale 1ns/1ps
module tb_text;
reg clk=0;always #5 clk=~clk;
reg rst=1,active=1,enabled=1;reg[9:0] x=0,y=0;reg[23:0] base_rgb=0;wire[23:0] out_rgb,old_rgb;
museum_floating_clock dut(.*);
baseline_clock original(.clk(clk),.rst(rst),.active(active),.enabled(enabled),.x(x),.y(y),.base_rgb(base_rgb),.out_rgb(old_rgb));
reg[23:0] columns[0:479];reg[23:0] home[0:307199];integer i,j,k,fd,offset,col,row,dx,dy;reg[23:0] expected;integer passed=0;
task frame;begin
 @(negedge clk);x=0;y=480;@(posedge clk);#1;
 if(dut.pos_x!==original.pos_x || dut.pos_y!==original.pos_y || dut.dir_x!==original.dir_x || dut.dir_y!==original.dir_y || dut.visible!==original.visible)$fatal(1,"outer motion/SW1 changed");
 @(negedge clk);x=1;@(posedge clk);#1;
end endtask
task pixel(input integer xx,yy);begin
 @(negedge clk);x=xx==0 ? 799 : xx-1;y=xx==0 ? yy-1 : yy;
 @(posedge clk);#1;x=xx;y=yy;base_rgb=home[yy*640+xx];#1;
end endtask
initial begin
 $readmemh("text_validation/columns.hex",columns);$readmemh("text_validation/home.hex",home);
 repeat(4)@(negedge clk);rst=0;
 for(i=0;i<60;i=i+1)begin frame();if(dut.scroll!=0)$fatal(1,"initial pause");end
 for(i=0;i<600;i=i+1)begin frame();if(dut.scroll!=((i+1)*25)/60)$fatal(1,"25 pixels per second rate");end
 if(dut.scroll!=250)$fatal(1,"250 pixels in 600 frames");
 i=0;while(dut.scroll!=0)begin frame();i=i+1;if(i>700)$fatal(1,"wrap watchdog");end
 if(dut.pause_frames!=60)$fatal(1,"loop pause");
 for(i=0;i<5000;i=i+1)frame();
 enabled=0;frame();if(dut.visible)$fatal(1,"SW1 hide");
 for(j=0;j<480;j=j+1)for(i=0;i<640;i=i+1)begin pixel(i,j);if(out_rgb!==base_rgb)$fatal(1,"disabled altered pixel");end
 enabled=1;frame();
 force dut.pos_x=173;force dut.pos_y=107;
 for(k=0;k<5;k=k+1)begin
  offset=k==0 ? 0 : k==1 ? 120 : k==2 ? 300 : 480;
  force dut.scroll=offset;
  if(k==4)begin force dut.pos_x=445;force dut.pos_y=448;end
  case(k)
   0:fd=$fopen("text_validation/text_start.ppm","w");
   1:fd=$fopen("text_validation/text_middle.ppm","w");
   2:fd=$fopen("text_validation/text_later.ppm","w");
   4:fd=$fopen("text_validation/text_boundary.ppm","w");
   3:fd=$fopen("text_validation/text_loop.ppm","w");
  endcase
  $fwrite(fd,"P3\n640 480\n255\n");
  for(j=0;j<480;j=j+1)for(i=0;i<640;i=i+1)begin
   pixel(i,j);expected=base_rgb;dx=i-(k==4 ? 445 : 173);dy=j-(k==4 ? 448 : 107);
   if(dx>=8 && dx<187 && dy>=4 && dy<28)begin
    col=(offset+dx-8)%504;row=dy-4;
    if(col<480 && columns[col][row])expected=0;
   end
   if(out_rgb!==expected)$fatal(1,"text pixel mismatch x=%0d y=%0d offset=%0d",i,j,offset);
   $fwrite(fd,"%0d %0d %0d\n",out_rgb[23:16],out_rgb[15:8],out_rgb[7:0]);
  end
  $fclose(fd);
 end
 release dut.scroll;release dut.pos_x;release dut.pos_y;
 active=0;pixel(200,120);if(out_rgb!==base_rgb)$fatal(1,"inactive altered");
 passed=1;$display("PASS floating text: adjusted horizontal bounds and original vertical motion/SW1; 60-frame pause, 25 pixels per 60 frames, 504-column wrap; 1843200 exact pixels including disabled and right/bottom boundary; 179x24 viewport");$finish;
end
initial begin #100000000;$fatal(1,"watchdog");end
endmodule

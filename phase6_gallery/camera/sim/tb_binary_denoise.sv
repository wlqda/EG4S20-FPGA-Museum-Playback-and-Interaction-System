`timescale 1ns/1ps
module tb_binary_denoise;
reg clk=0;always #5 clk=~clk;reg rst=1,begin_frame=0,end_frame=0,sample_valid=0;
reg[6:0] x=0;reg[5:0] y=0;reg[2:0] data=0;wire out_valid,out_end;wire[6:0] out_x;wire[5:0] out_y;wire[2:0] out_data;
reg[2:0] image[0:4799];integer count=0,pattern,i,j,dx,dy,n;reg[2:0] expected;reg passed=0;
camera_binary_denoise dut(.*);
always @(negedge clk)if(!rst && out_valid)begin
 if(out_x>=80 || out_y>=60)$fatal(1,"output coordinate");
 if(out_y*80+out_x!=count)$fatal(1,"order got %d expected %d",out_y*80+out_x,count);
 n=0;for(integer yy=-1;yy<=1;yy=yy+1)for(integer xx=-1;xx<=1;xx=xx+1)begin
 dx=out_x+xx;dy=out_y+yy;
 if((xx!=0 || yy!=0) && dx>=0 && dx<80 && dy>=0 && dy<60)n=n+image[dy*80+dx][0];
 end
 expected=image[count][0] && n>=5 ? image[count] : 0;
 if(out_data!==expected)$fatal(1,"filter at %d got %b expected %b neighbors%d",count,out_data,expected,n);
 count=count+1;
end
initial begin
repeat(4)@(negedge clk);rst=0;
for(pattern=0;pattern<4;pattern=pattern+1)begin
 for(i=0;i<4800;i=i+1)begin
 case(pattern)
 0:image[i]=7;
 1:image[i]=(i%80>=30 && i%80<46 && i/80>=20 && i/80<38) ? 7 : (i==100 || i==4799 ? 1 : 0);
 2:image[i]=$random;
 3:image[i]=(i%80==0 || i%80==79 || i/80==0 || i/80==59) ? 7 : 0;
 endcase
 end
 count=0;begin_frame=1;@(negedge clk);begin_frame=0;
 for(j=0;j<60;j=j+1)for(i=0;i<80;i=i+1)begin
 x=i;y=j;data=image[j*80+i];sample_valid=1;@(negedge clk);sample_valid=0;repeat(1+(i%3))@(negedge clk);
 end
 end_frame=1;@(negedge clk);end_frame=0;
 wait(out_end);@(negedge clk);if(count!=4800)$fatal(1,"missing pixels %d",count);repeat(3)@(negedge clk);
end
passed=1;$display("PASS binary denoise: four full frames, golden 3x3, seeds, borders, stalls, no frame leakage");$finish;
end
initial begin #10000000;$fatal(1,"watchdog");end
endmodule

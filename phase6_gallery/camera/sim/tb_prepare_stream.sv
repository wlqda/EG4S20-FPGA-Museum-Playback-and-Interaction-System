`timescale 1ns/1ps
module tb_prepare_stream;
reg wr_clk=0,rd_clk=0;always #5 wr_clk=~wr_clk;always #7 rd_clk=~rd_clk;
reg wr_rst=1,rd_rst=1,pixel_valid=0,frame_start=0,frame_done=0,frame_good=0;
reg [15:0] pixel=16'hcbe7,pixel_x=0,pixel_y=0;
reg recalibrate=1,processing_done=0;
wire de,fresh_frame,abort_frame,stream_fault;wire [9:0] x,y;wire [23:0] rgb;
reg passed=0;integer cells=0,frames=0,before_frames,delay_count=0;
camera_source_stream #(.INPUT_WIDTH(16),.INPUT_HEIGHT(12),.FIFO_BITS(4),.WAIT_LIMIT(200)) dut(.*);
always @(posedge rd_clk)begin
 processing_done<=0;
 if(abort_frame)cells=0;
 if(delay_count>0)begin delay_count=delay_count-1;if(delay_count==0)processing_done<=1;end
 if(de)begin
  if(x==31 && y==23)begin
   if(cells!=12)$fatal(1,"partial preparation preview");cells=0;frames=frames+1;
   if(!recalibrate)delay_count=20;
  end else begin
   if(x!=(cells%4)*8 || y!=(cells/4)*8)$fatal(1,"preparation raster order");
   cells=cells+1;
  end
 end
end
task boundary;begin
 @(negedge wr_clk);frame_start=1;frame_done=1;frame_good=1;
 @(negedge wr_clk);frame_start=0;frame_done=0;frame_good=0;
end endtask
task pixels;begin
 for(integer yy=0;yy<12;yy=yy+1)for(integer xx=0;xx<16;xx=xx+1)begin
  @(negedge wr_clk);pixel_valid=1;pixel_x=xx;pixel_y=yy;
  @(negedge wr_clk);pixel_valid=0;
 end
end endtask
initial begin
 repeat(5)@(negedge rd_clk);wr_rst=0;rd_rst=0;boundary;
 repeat(20)begin pixels;boundary;repeat(30)@(negedge rd_clk);end
 if(stream_fault || frames!=20)$fatal(1,"held preparation stalls/overflows source frames=%d fault=%b",frames,stream_fault);
 recalibrate=0;before_frames=frames;
 repeat(3)begin pixels;boundary;repeat(60)@(negedge rd_clk);end
 if(stream_fault || frames!=before_frames+3)$fatal(1,"release does not resume analysis");
 // A mid-frame KEY2 must not stop the producer/consumer or publish a partial preview.
 fork pixels;begin repeat(30)@(negedge rd_clk);recalibrate=1;end join
 boundary;repeat(30)@(negedge rd_clk);
 repeat(10)begin pixels;boundary;repeat(30)@(negedge rd_clk);end
 if(stream_fault)$fatal(1,"repeat preparation fault");
 passed=1;$display("PASS PREPARE STREAM: sustained camera traffic during held/repeated recalibration, complete preview and release; no FIFO overflow or analysis deadline");$finish;
end
initial begin #1000000;$fatal(1,"watchdog");end
endmodule

`timescale 1ns/1ps
module tb_vertical_roi;
reg clk=0;always #20 clk=~clk;
reg rst=1,de=0,fresh=0;reg [9:0] x=0,y=0;reg [23:0] rgb=0;
wire [1:0] ready,done,valid,clipped;wire [3:0] edges[0:1];
wire [9:0] cx[0:1],cy[0:1];wire [12:0] area[0:1];
reg passed=0;
genvar g;generate for(g=0;g<2;g=g+1)begin:a
camera_foreground_debug #(.WARMUP_CYCLES(0),.STABLE_FRAMES(2),.PALM_FILTER(1),.TRACK_FILTER(0),.SOURCE_MODE(1),.SKIN_RECONSTRUCT(1),.SPATIAL_SCENE_GATE(1),.MAX_AREA(2400),.PALM_MAX_ASPECT(4),.POSE_FEATURES(1),.ROI_Y0(g==0 ? 48 : 16),.ROI_Y1(g==0 ? 432 : 464)) dut(
.clk(clk),.rst(rst),.have_frame(1'b1),.recalibrate(1'b0),.fresh_frame(fresh),.de(de),.hs(1'b1),.vs(1'b1),.x(x),.y(y),.rgb(rgb),.pipeline_rates(32'd0),.pipeline_rates_valid(1'b0),.selection_reference(41'd0),.background_ready(ready[g]),.processing_done(done[g]),.pose_valid(valid[g]),.pose_clipped(clipped[g]),.pose_edges(edges[g]),.centroid_x(cx[g]),.centroid_y(cy[g]),.pose_area(area[g]),.out_de(),.out_hs(),.out_vs(),.out_rgb(),.target_valid(),.target_area(),.mask_valid(),.mask_x(),.mask_y(),.mask_bits(),.analysis_status(),.pose_sample(),.pose_id(),.pose_counts());
end endgenerate
reg [1:0] seen;
always @(posedge clk)if(rst)seen<=0;else seen<=seen|done;
task frame(input integer top,bottom);
integer xx,yy,n;
begin
@(negedge clk);seen=0;
for(yy=0;yy<480;yy=yy+8)for(xx=0;xx<640;xx=xx+8)begin
@(negedge clk);de=1;x=xx;y=yy;fresh=xx==0 && yy==0;
rgb=(xx>=280 && xx<360 && yy>=top && yy<bottom) ? 24'hc08040 : 24'h303030;
@(negedge clk);de=0;fresh=0;
end
@(negedge clk);de=1;x=639;y=479;rgb=0;
@(negedge clk);de=0;n=0;
while(seen!=3 && n<40000)begin @(negedge clk);n=n+1;end
if(seen!=3)$fatal(1,"processing timeout");
repeat(4)@(negedge clk);
end endtask
initial begin
repeat(5)@(negedge clk);rst=0;
repeat(5)frame(0,0);
if(ready!=3)$fatal(1,"background not ready");
frame(176,304);if(valid!=3 || clipped!=0 || area[0]!=area[1] || cy[0]!=cy[1])$fatal(1,"central geometry changed");
frame(32,160);if(valid!=3 || !clipped[0] || clipped[1] || area[1]!=160 || edges[0]!=4)$fatal(1,"upper expansion failed");
frame(320,448);if(valid!=3 || !clipped[0] || clipped[1] || area[1]!=160 || edges[0]!=8)$fatal(1,"lower expansion failed");
frame(8,136);if(!valid[1] || !clipped[1] || edges[1]!=4)$fatal(1,"new upper boundary not protected");
frame(344,472);if(!valid[1] || !clipped[1] || edges[1]!=8)$fatal(1,"new lower boundary not protected");
passed=1;$display("PASS vertical ROI: background, central equivalence, old/new upper and lower boundaries, new edge protection");$finish;
end
initial begin #30000000;$fatal(1,"watchdog");end
endmodule

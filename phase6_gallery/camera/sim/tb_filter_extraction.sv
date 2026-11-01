`timescale 1ns/1ps
module tb_filter_extraction;
reg clk=0;always #5 clk=~clk;reg rst=1,recalibrate=0,fresh_frame=0,de=0;reg[9:0] x=0,y=0;reg[23:0] rgb=0;
wire background_ready,processing_done,pose_sample,pose_valid;wire[12:0] pose_area;wire[31:0] pose_id;wire[143:0] pose_counts;wire[3:0] pose_edges;wire pose_clipped;reg passed=0;integer i,j,k;
camera_foreground_debug #(.WARMUP_CYCLES(0),.STABLE_FRAMES(1),.ROI_Y0(16),.ROI_Y1(464),.PALM_FILTER(1),.TRACK_FILTER(0),.SOURCE_MODE(1),.SKIN_RECONSTRUCT(1),.SPATIAL_SCENE_GATE(1),.MAX_AREA(2400),.PALM_MAX_ASPECT(4),.POSE_FEATURES(1),.BINARY_FILTER(5)) dut(
.clk(clk),.rst(rst),.have_frame(1'b1),.recalibrate(recalibrate),.fresh_frame(fresh_frame),.pipeline_rates(32'd0),.pipeline_rates_valid(1'b0),.de(de),.hs(1'b1),.vs(1'b1),.selection_reference(41'd0),.x(x),.y(y),.rgb(rgb),.out_de(),.out_hs(),.out_vs(),.out_rgb(),.background_ready(background_ready),.target_valid(),.centroid_x(),.centroid_y(),.target_area(),.processing_done(processing_done),.mask_valid(),.mask_x(),.mask_y(),.mask_bits(),.analysis_status(),.pose_sample(pose_sample),.pose_valid(pose_valid),.pose_clipped(pose_clipped),.pose_id(pose_id),.pose_counts(pose_counts),.pose_area(pose_area),.pose_edges(pose_edges));
task frame(input integer hand);begin
for(j=0;j<60;j=j+1)for(i=0;i<80;i=i+1)begin
@(negedge clk);de=1;fresh_frame=i==0 && j==0;x=i*8;y=j*8;
rgb=hand!=0 && ((i>=30 && i<50 && j>=20 && j<40) || (i==15 && j==15)) ? 24'hc08060 : 24'h101010;
@(negedge clk);de=0;fresh_frame=0;
end
@(negedge clk);de=1;x=639;y=479;@(negedge clk);de=0;
k=0;while(!processing_done && k<40000)begin @(negedge clk);k=k+1;end
if(k==40000)$fatal(1,"processing exceeded source timeout");
repeat(3)@(negedge clk);
end endtask
initial begin
repeat(4)@(negedge clk);rst=0;
frame(0);frame(0);if(!background_ready)$fatal(1,"background not ready");
frame(1);if(!pose_valid || pose_area!=396)$fatal(1,"filtered selected region valid%b area%d",pose_valid,pose_area);
frame(1);if(!pose_valid || pose_area!=396)$fatal(1,"stationary hand lost");
passed=1;$display("PASS extraction: auto background, FILTER5 reaches real CCL, isolated noise excluded, 396-pixel hand retained, processing within 40000 cycles");$finish;
end
initial begin #10000000;$fatal(1,"watchdog");end
endmodule

`timescale 1ns/1ps
module tb_camera_source_stream;
    reg wr_clk=0,rd_clk=0;always #5 wr_clk=~wr_clk;always #7 rd_clk=~rd_clk;
    reg wr_rst=1,rd_rst=1,pixel_valid=0,frame_start=0,frame_done=0,frame_good=0;
    reg [15:0] pixel=16'hcbe7,pixel_x=0,pixel_y=0;
    reg recalibrate=0,processing_done=0,allow_done=1;
    wire de,fresh_frame,abort_frame,stream_fault;wire [9:0] x,y;wire [23:0] rgb;
    reg passed=0;integer cells=0,completed=0,delay_count=0,before_recovery;reg opened=0;
    camera_source_stream #(.INPUT_WIDTH(16),.INPUT_HEIGHT(12),.FIFO_BITS(4),.WAIT_LIMIT(200)) dut(.*);
    always @(posedge rd_clk)begin
        processing_done<=0;
        if(rd_rst)begin cells=0;completed=0;delay_count=0;end
        else begin
            if(delay_count>0)begin
                delay_count=delay_count-1;
                if(delay_count==0 && allow_done)processing_done<=1;
            end
            if(abort_frame)cells=0;
            if(de)begin
                if(x==31 && y==23)begin
                    if(cells!=12)$fatal(1,"Partial frame closed: %d cells",cells);
                    completed=completed+1;cells=0;delay_count=20;
                end else begin
                    if(x!=(cells%4)*8 || y!=(cells/4)*8)$fatal(1,"Source coordinate/order mismatch");
                    if(fresh_frame!=(cells==0))$fatal(1,"Fresh pulse is not the first cell");
                    if(rgb!==24'hce7d39)$fatal(1,"RGB565 expansion mismatch %h",rgb);
                    cells=cells+1;
                end
            end
        end
    end
    task boundary(input bit good);
        begin
            @(negedge wr_clk);frame_start=1;frame_done=opened;frame_good=good;pixel_valid=0;opened=1;
            @(negedge wr_clk);frame_start=0;frame_done=0;frame_good=0;
        end
    endtask
    task pixels;
        begin
            for(integer yy=0;yy<12;yy=yy+1)for(integer xx=0;xx<16;xx=xx+1)begin
                @(negedge wr_clk);pixel_valid=1;pixel_x=xx;pixel_y=yy;
                @(negedge wr_clk);pixel_valid=0;
            end
        end
    endtask
    initial begin
        repeat(5)@(negedge rd_clk);wr_rst=0;rd_rst=0;
        boundary(0);
        repeat(3)begin pixels;boundary(1);repeat(80)@(negedge rd_clk);end
        if(completed!=3 || stream_fault)$fatal(1,"Continuous source frames lost");
        pixels;boundary(0);repeat(80)@(negedge rd_clk);
        if(completed!=3)$fatal(1,"Bad frame committed");
        // Preparation resets analysis, but complete preview frames must continue draining.
        fork
            pixels;
            begin repeat(30)@(negedge rd_clk);recalibrate=1;@(negedge rd_clk);recalibrate=0;end
        join
        boundary(1);repeat(80)@(negedge rd_clk);
        if(completed!=4)$fatal(1,"KEY2 interrupted the complete preview frame");
        pixels;boundary(1);repeat(80)@(negedge rd_clk);
        if(completed!=5)$fatal(1,"KEY2 failed to resume complete frame");
        // Hold the analysis consumer while more frames arrive, force overflow,
        // then require a new boundary and full frame before another completion.
        allow_done=0;pixels;boundary(1);
        repeat(4)begin pixels;boundary(1);end
        repeat(300)@(negedge rd_clk);
        if(!stream_fault)$fatal(1,"Overflow/deadline was not reported");
        before_recovery=completed;
        allow_done=1;boundary(1);pixels;boundary(1);repeat(150)@(negedge rd_clk);
        if(cells!=0 || completed!=before_recovery+1)$fatal(1,"Recovery did not resume a complete frame");
        passed=1;$display("PASS SOURCE STREAM: continuous complete frames, RGB, bad frame, KEY2, overflow and resynchronization");$finish;
    end
    initial begin #200000;$fatal(1,"Source stream timeout");end
endmodule

module tb_camera_source_pipeline #(parameter RECONSTRUCT=0,LOW_CONTRAST=0,POSE=0);
    reg wr_clk=0,rd_clk=0;always #25 wr_clk=~wr_clk;always #20 rd_clk=~rd_clk;
    reg wr_rst=1,rd_rst=1,pixel_valid=0,frame_start=0,frame_done=0,frame_good=0;
    reg [15:0] pixel=0,pixel_x=0,pixel_y=0;
    reg recalibrate=0;
    wire de,fresh_frame,abort_frame,stream_fault,processing_done;
    wire [9:0] x,y;wire [23:0] rgb;
    wire background_ready,target_valid,out_de,out_hs,out_vs,mask_valid;
    wire [6:0] mask_x;wire [5:0] mask_y;wire [2:0] mask_bits;
    wire [223:0] analysis_status;wire [40:0] selection_reference=0;wire [23:0] out_rgb;wire [9:0] centroid_x,centroid_y;wire [12:0] target_area;
    wire [31:0] pipeline_rates=0;wire pipeline_rates_valid=0;
    wire have_frame=1,clk=rd_clk,rst=rd_rst,hs=1,vs=1;
    wire extraction_reset=recalibrate || abort_frame;
    reg passed=0,opened=0;integer completed=0;
    wire pose_sample,pose_valid,pose_clipped;wire [31:0] pose_id;wire [143:0] pose_counts;wire [12:0] pose_area;
    integer pose_results=0,total;
    always @(posedge clk)if(POSE && pose_sample && pose_valid)begin
        total=0;for(integer b=0;b<16;b=b+1)total=total+pose_counts[b*9+:9];
        if(total!=pose_area || total!=36 || pose_clipped)$fatal(1,"Headless pose output misaligned area=%d total=%d clipped=%b",pose_area,total,pose_clipped);
        pose_results=pose_results+1;
    end
    camera_source_stream #(.INPUT_WIDTH(64),.INPUT_HEIGHT(48)) stream(.*);
    camera_foreground_debug #(.WIDTH(128),.HEIGHT(96),.WARMUP_CYCLES(10),.STABLE_FRAMES(2),
        .ROI_X0(8),.ROI_X1(120),.ROI_Y0(8),.ROI_Y1(88),.MIN_AREA(12),.MAX_AREA(150),
        .PALM_FILTER(1),.TRACK_FILTER(!POSE),.SOURCE_MODE(1),.SKIN_RECONSTRUCT(RECONSTRUCT),.SPATIAL_SCENE_GATE(RECONSTRUCT),
        .POSE_FEATURES(POSE),.BACKGROUND_RAM_STYLE(POSE ? "bram_32k" : "bram_9k")) extraction(
        .clk(clk),.rst(rst),.have_frame(have_frame),.recalibrate(extraction_reset),.fresh_frame(fresh_frame),
        .de(de),.hs(hs),.vs(vs),.x(x),.y(y),.rgb(rgb),.pipeline_rates(pipeline_rates),.pipeline_rates_valid(pipeline_rates_valid),
        .selection_reference(41'd0),.out_de(out_de),.out_hs(out_hs),.out_vs(out_vs),.out_rgb(out_rgb),.background_ready(background_ready),.target_valid(target_valid),
        .centroid_x(centroid_x),.centroid_y(centroid_y),.target_area(target_area),.processing_done(processing_done),
        .mask_valid(mask_valid),.mask_x(mask_x),.mask_y(mask_y),.mask_bits(mask_bits),.analysis_status(analysis_status),
        .pose_sample(pose_sample),.pose_valid(pose_valid),.pose_clipped(pose_clipped),.pose_id(pose_id),.pose_counts(pose_counts),.pose_area(pose_area),.pose_edges());
    // Same sparse frames through the old strict intersection, for a causal
    // low-contrast comparison rather than only checking the new implementation.
    wire strict_valid;
    camera_foreground_debug #(.WIDTH(128),.HEIGHT(96),.WARMUP_CYCLES(10),.STABLE_FRAMES(2),
        .ROI_X0(8),.ROI_X1(120),.ROI_Y0(8),.ROI_Y1(88),.MIN_AREA(12),.MAX_AREA(150),
        .PALM_FILTER(1),.TRACK_FILTER(1),.SOURCE_MODE(1)) strict_extraction(
        .clk(clk),.rst(rst),.have_frame(have_frame),.recalibrate(extraction_reset),.fresh_frame(fresh_frame),
        .de(de),.hs(hs),.vs(vs),.x(x),.y(y),.rgb(rgb),.pipeline_rates(pipeline_rates),.pipeline_rates_valid(pipeline_rates_valid),
        .selection_reference(41'd0),.out_de(),.out_hs(),.out_vs(),.out_rgb(),.background_ready(),.target_valid(strict_valid),
        .centroid_x(),.centroid_y(),.target_area(),.processing_done(),
        .mask_valid(),.mask_x(),.mask_y(),.mask_bits(),.analysis_status(),
        .pose_sample(),.pose_valid(),.pose_clipped(),.pose_id(),.pose_counts(),.pose_area(),.pose_edges());
    // Preview never acknowledges a frame. Analysis must continue anyway.
    wire [15:0] rd_pixel;wire preview_frame;wire [31:0] published_frames,skipped_frames;
    camera_preview_buffer #(.INPUT_WIDTH(64),.INPUT_HEIGHT(48)) preview(
        .wr_clk(wr_clk),.wr_rst(wr_rst),.pixel_valid(pixel_valid),.frame_start(frame_start),.frame_done(frame_done),.frame_good(frame_good),
        .pixel(pixel),.pixel_x(pixel_x),.pixel_y(pixel_y),.rd_clk(rd_clk),.rd_rst(rd_rst),.vblank(1'b0),.rd_addr(8'd0),
        .rd_pixel(rd_pixel),.have_frame(preview_frame),.published_frames(published_frames),.skipped_frames(skipped_frames),.displayed_frame_update());
    always @(posedge rd_clk)if(processing_done)completed=completed+1;
    task boundary(input bit good=1);
        begin
            @(negedge wr_clk);frame_start=1;frame_done=opened;frame_good=good;opened=1;
            @(negedge wr_clk);frame_start=0;frame_done=0;frame_good=0;
        end
    endtask
    task frame(input bit hand,input bit good=1);
        begin
            for(integer yy=0;yy<48;yy=yy+1)for(integer xx=0;xx<64;xx=xx+1)begin
                @(negedge wr_clk);pixel_valid=1;pixel_x=xx;pixel_y=yy;
                if(LOW_CONTRAST)begin
                    // Expanded skin luma is 128, close to background luma 131.
                    // Only one row (6 cells) has strong background difference.
                    pixel=hand && xx>=20 && xx<44 && yy>=12 && yy<36 ?
                        (yy<16 ? 16'h8203 : 16'hcbe7) : 16'h8410;
                end else pixel=hand && xx>=20 && xx<44 && yy>=12 && yy<36 ? 16'hcbe7 : 16'h3186;
                @(negedge wr_clk);pixel_valid=0;
            end
            boundary(good);repeat(5000)@(negedge rd_clk);
        end
    endtask
    initial begin
        repeat(6)@(negedge rd_clk);wr_rst=0;rd_rst=0;
        boundary;
        repeat(5)frame(0);
        if(!background_ready)$fatal(1,"Sparse background never became ready");
        repeat(6)frame(1);
        if(!target_valid || target_area<12)$fatal(1,"Sparse hand failed to track");
        if(RECONSTRUCT && LOW_CONTRAST)begin
            if(target_area!=36 || centroid_x!=60 || centroid_y!=44 || strict_valid)
                $fatal(1,"Reconstruction did not restore full geometry over strict baseline A=%d X=%d Y=%d old=%b",target_area,centroid_x,centroid_y,strict_valid);
            if(!POSE && extraction.regions.analysis.motion_count!=0)
                $fatal(1,"Static hold incorrectly retained temporal motion");
        end
        if(completed!=11 || published_frames!=1 || skipped_frames<8 || stream_fault)
            $fatal(1,"Source depends on stalled preview: completed=%d published=%d skipped=%d fault=%b",completed,published_frames,skipped_frames,stream_fault);
        frame(1,0);
        if(target_valid || background_ready)$fatal(1,"Bad source frame retained valid tracking/background");
        repeat(5)frame(0);repeat(6)frame(1);
        if(!target_valid || completed!=22 || stream_fault)$fatal(1,"Bad-frame recovery failed");
        if(POSE && pose_results<10)$fatal(1,"Pose mode did not publish fresh results after source recovery");
        passed=1;$display("PASS SOURCE PIPELINE: reconstruct=%0d low_contrast=%0d sparse background, tracking, hold, bad-frame recovery and 11 results with stalled preview",RECONSTRUCT,LOW_CONTRAST);$finish;
    end
    initial begin #15000000;$fatal(1,"Source pipeline timeout");end
endmodule

module tb_camera_source_budget;
    reg wr_clk=0,rd_clk=0;always #20 wr_clk=~wr_clk;
    initial begin #3;forever #20 rd_clk=~rd_clk;end
    reg wr_rst=1,rd_rst=1,pixel_valid=0,frame_start=0,frame_done=0,frame_good=0;
    reg [15:0] pixel=16'hcbe7,pixel_x=0,pixel_y=0;
    reg recalibrate=0,processing_done=0,opened=0;
    wire de,fresh_frame,abort_frame,stream_fault;wire [9:0] x,y;wire [23:0] rgb;
    reg passed=0;integer cells=0,completed=0,delay_count=0;
    camera_source_stream dut(.*);
    always @(posedge rd_clk)begin
        processing_done<=0;
        if(abort_frame)cells=0;
        if(de)begin
            if(x==639 && y==479)begin
                if(cells!=4800)$fatal(1,"Full-size frame lost cells");
                cells=0;completed=completed+1;delay_count=34020;
            end else begin
                if(x!=(cells%80)*8 || y!=(cells/80)*8)$fatal(1,"Full-size raster order changed");
                cells=cells+1;
            end
        end
        if(delay_count>0)begin delay_count=delay_count-1;if(delay_count==0)processing_done<=1;end
    end
    task boundary;
        begin
            @(negedge wr_clk);frame_start=1;frame_done=opened;frame_good=1;opened=1;
            @(negedge wr_clk);frame_start=0;frame_done=0;frame_good=0;
        end
    endtask
    initial begin
        repeat(5)@(negedge rd_clk);wr_rst=0;rd_rst=0;boundary;
        repeat(3)begin
            for(integer yy=0;yy<240;yy=yy+1)for(integer xx=0;xx<320;xx=xx+1)begin
                @(negedge wr_clk);pixel_valid=1;pixel_x=xx;pixel_y=yy;
                @(negedge wr_clk);pixel_valid=0;
            end
            boundary;
        end
        repeat(40000)@(negedge rd_clk);
        if(completed!=3 || stream_fault)$fatal(1,"FIFO failed full-size 25MHz source / 34020-cycle processing budget");
        passed=1;$display("PASS SOURCE BUDGET: 3 full 320x240 frames at 25MHz, no blanking, 34020-cycle analysis pause, no loss");$finish;
    end
    initial begin #25000000;$fatal(1,"Full-size source budget timeout");end
endmodule

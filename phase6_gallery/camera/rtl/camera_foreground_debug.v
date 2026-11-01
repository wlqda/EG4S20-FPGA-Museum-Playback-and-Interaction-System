// 25MHz foreground analysis. Input is a complete display-owned raster or the
// independent, complete source-frame sparse raster. Fixed 80x60 background.
module camera_foreground_debug #(
    parameter integer WIDTH=640,HEIGHT=480,GRID_W=WIDTH/8,GRID_H=HEIGHT/8,
    parameter integer WARMUP_CYCLES=125000000,DIFF_THRESHOLD=24,
    parameter integer ROI_X0=64,ROI_X1=576,ROI_Y0=48,ROI_Y1=432,
    parameter integer MIN_AREA=24,MAX_AREA=1200,STABLE_FRAMES=6,PALM_MAX_ASPECT=3,
    parameter HAND_FILTER=1,PALM_FILTER=0,TRACK_FILTER=0,SOURCE_MODE=0,SKIN_RECONSTRUCT=0,SPATIAL_SCENE_GATE=0,
    parameter integer BINARY_FILTER=0,
    parameter POSE_FEATURES=0,BACKGROUND_RAM_STYLE="bram_9k",IDENTITY_SELECT=0
)(
    input wire clk,rst,have_frame,recalibrate,fresh_frame,input wire de,hs,vs,
    input wire [9:0] x,y,input wire [23:0] rgb,
    input wire [31:0] pipeline_rates,input wire pipeline_rates_valid,
    input wire [40:0] selection_reference,
    output wire out_de,out_hs,out_vs,output wire [23:0] out_rgb,
    output reg background_ready,output wire target_valid,
    output wire [9:0] centroid_x,centroid_y,output wire [12:0] target_area,
    output wire processing_done,mask_valid,output wire [6:0] mask_x,output wire [5:0] mask_y,
    output wire [2:0] mask_bits,output wire [223:0] analysis_status,
    output wire pose_sample,pose_valid,pose_clipped,output wire [31:0] pose_id,
    output wire [143:0] pose_counts,output wire [12:0] pose_area,output wire [3:0] pose_edges
);
    reg measurement_valid;
    reg [9:0] measurement_x,measurement_y;
    reg [12:0] measurement_area;
    localparam PIXELS=GRID_W*GRID_H,AW=$clog2(PIXELS);
    localparam LEFT_COLS=(WIDTH/2+7)/8,ROI_COL0=(ROI_X0+7)/8,ROI_COL1=(ROI_X1+7)/8,
        ROI_ROWS=(ROI_Y1+7)/8-(ROI_Y0+7)/8,
        LEFT_ROI_COLS=ROI_COL0>=LEFT_COLS ? 0 : (ROI_COL1<LEFT_COLS ? ROI_COL1 : LEFT_COLS)-ROI_COL0,
        LEFT_REFERENCE=LEFT_COLS*GRID_H-LEFT_ROI_COLS*ROI_ROWS,
        RIGHT_REFERENCE=(GRID_W-LEFT_COLS)*GRID_H-(ROI_COL1-ROI_COL0-LEFT_ROI_COLS)*ROI_ROWS,
        LCW=LEFT_REFERENCE>0 ? $clog2(LEFT_REFERENCE+1) : 1,
        RCW=RIGHT_REFERENCE>0 ? $clog2(RIGHT_REFERENCE+1) : 1;
    reg [LCW-1:0] outside_left,reported_left;
    reg [RCW-1:0] outside_right,reported_right;
    wire [12:0] scene_left=reported_left,scene_right=reported_right;
    (* ram_style=BACKGROUND_RAM_STYLE *) reg [7:0] background[0:PIXELS-1];
    reg [7:0] background_q,grey_q;
    reg [23:0] rgb_q;
    reg [9:0] x_q,y_q;
    reg de_q,hs_q,vs_q;
    reg [26:0] warmup;
    reg capturing;
    reg candidate_valid,fresh_pending,comparison_frame;
    reg [3:0] stable_count;
    reg [12:0] reported_global;
    reg [12:0] reported_raw,reported_skin;
    reg [12:0] reported_core;
    reg [2:0] rejection;
    wire frame_first=de_q && x_q==0 && y_q==0;
    wire frame_last=de_q && x_q==WIDTH-1 && y_q==HEIGHT-1;
    reg [12:0] area,global_changed,raw_area,skin_area;
    wire [9:0] weighted={2'b0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'b0,rgb[7:0]};
    wire [7:0] grey=weighted[9:2];
    wire [AW-1:0] address=de ? (y>>3)*GRID_W+(x>>3) : {AW{1'b0}};
    wire first=de && x==0 && y==0;
    wire last=de && x==WIDTH-1 && y==HEIGHT-1;
    wire start_capture=first && have_frame && (fresh_pending || fresh_frame) && !background_ready &&
        !candidate_valid && !capturing && warmup==WARMUP_CYCLES;
    wire sample=de && x[2:0]==0 && y[2:0]==0;
    // RAM has no reset; classification is disabled until an entire background
    // frame is captured. Read-during-write data is never used for detection.
    always @(posedge clk)begin
        background_q<=background[address];
        if(!rst && !recalibrate && sample && (capturing || start_capture))begin
            background[address]<=grey;
            // EG4 BRAM32K has no read-before-write mode. During background
            // capture its read data is not detection input; use write-through.
            if(POSE_FEATURES)background_q<=grey;
        end
    end
    always @(posedge clk)begin
        if(rst)begin
            warmup<=0;capturing<=0;background_ready<=0;candidate_valid<=0;
            stable_count<=0;fresh_pending<=0;comparison_frame<=0;
            rgb_q<=0;grey_q<=0;x_q<=0;y_q<=0;de_q<=0;hs_q<=1;vs_q<=1;
        end else begin
            rgb_q<=rgb;grey_q<=grey;x_q<=x;y_q<=y;de_q<=de;hs_q<=hs;vs_q<=vs;
            if(recalibrate)begin
                warmup<=WARMUP_CYCLES;capturing<=0;background_ready<=0;candidate_valid<=0;
                stable_count<=0;fresh_pending<=0;comparison_frame<=0;
            end else begin
                if(fresh_frame)fresh_pending<=1;
                if(frame_first)begin
                    comparison_frame<=candidate_valid && (fresh_pending || fresh_frame);
                    fresh_pending<=0;
                end
                if(!have_frame)warmup<=0;
                else if(warmup<WARMUP_CYCLES)warmup<=warmup+1'b1;
                if(start_capture)capturing<=1;
                if(last && capturing)begin capturing<=0;candidate_valid<=1;end
                if(frame_last && comparison_frame && !background_ready)begin
                    if(raw_area<=(ROI_X1-ROI_X0)*(ROI_Y1-ROI_Y0)/64/20 && global_changed<=PIXELS/20)begin
                        if(stable_count==STABLE_FRAMES-1)begin background_ready<=1;stable_count<=STABLE_FRAMES;end
                        else stable_count<=stable_count+1'b1;
                    end else begin candidate_valid<=0;stable_count<=0;end
                end
            end
        end
    end
    wire [7:0] difference=grey_q>=background_q ? grey_q-background_q : background_q-grey_q;
    wire changed=candidate_valid && difference>=DIFF_THRESHOLD;
    wire in_roi=x_q>=ROI_X0 && x_q<ROI_X1 && y_q>=ROI_Y0 && y_q<ROI_Y1;
    // A foreground subject can change more than half the frame. Require
    // distributed outside-ROI evidence before calling that a scene change.
    // Missing either reference half falls back to the old global protection.
    wire reference_available=SPATIAL_SCENE_GATE && LEFT_REFERENCE>0 && RIGHT_REFERENCE>0;
    wire scene_block=global_changed>=PIXELS/2 && (!reference_available ||
        (outside_left>=(LEFT_REFERENCE+1)/2 && outside_right>=(RIGHT_REFERENCE+1)/2));
    wire reported_scene_block=reported_global>=PIXELS/2 && (!reference_available ||
        (reported_left>=(LEFT_REFERENCE+1)/2 && reported_right>=(RIGHT_REFERENCE+1)/2));
    wire skin,hand_eligible;
    generate if(!POSE_FEATURES)begin: temporal_filter
    camera_hand_candidate #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) hand_filter(
        .clk(clk),.rst(rst),.recalibrate(recalibrate),.fresh_frame(fresh_frame),
        .de(de),.x(x),.y(y),.rgb(rgb),.changed(changed),.skin(skin),.eligible(hand_eligible));
    end else begin: pose_skin
        wire [7:0] red=rgb_q[23:16],green=rgb_q[15:8],blue=rgb_q[7:0];
        assign skin=red>40 && green>20 && blue>10 && {1'b0,red}>={1'b0,green}+9'd4 &&
            {1'b0,red}>={1'b0,blue}+9'd8 && red-blue>12;
        assign hand_eligible=skin;
    end endgenerate
    wire raw_fg=de_q && changed && in_roi;
    wire selected=changed && (PALM_FILTER ? skin : (!HAND_FILTER || hand_eligible));
    wire fg=de_q && selected && in_roi;
    wire region_fg=SKIN_RECONSTRUCT ? de_q && skin && in_roi : fg;
    wire coarse_sample=de_q && x_q[2:0]==0 && y_q[2:0]==0;
    wire filtered_valid,filtered_end,filtered_dense,filtered_motion,filtered_foreground;
    wire [6:0] filtered_x;wire [5:0] filtered_y;
    generate if(BINARY_FILTER!=0)begin: binary_denoise
      camera_binary_denoise #(.GW(GRID_W),.GH(GRID_H),.THRESHOLD(BINARY_FILTER)) denoise(
       .clk(clk),.rst(rst || recalibrate),.begin_frame(first),.end_frame(frame_last),
       .sample_valid(coarse_sample),.x(x_q[9:3]),.y(y_q[8:3]),
       .data({raw_fg && skin,raw_fg && hand_eligible,region_fg && background_ready}),
       .out_valid(filtered_valid),.out_end(filtered_end),.out_x(filtered_x),.out_y(filtered_y),
       .out_data({filtered_foreground,filtered_motion,filtered_dense}));
    end else begin: binary_bypass
      assign filtered_valid=coarse_sample;assign filtered_end=frame_last;
      assign filtered_x=x_q[9:3];assign filtered_y=y_q[8:3];
      assign filtered_dense=region_fg && background_ready;
      assign filtered_motion=raw_fg && hand_eligible;assign filtered_foreground=raw_fg && skin;
    end endgenerate
    wire region_done,region_valid,region_overflow;
    wire [12:0] region_area,region_core,region_motion;
    wire [143:0] region_shape;
    wire [18:0] region_sx,region_sy;
    wire [6:0] region_lx,region_hx;
    wire [5:0] region_ly,region_hy;
    wire track_locked,track_update,track_reference_valid;
    wire [9:0] tracked_x,tracked_y,tracked_width,tracked_height;
    generate if(PALM_FILTER)begin: regions
        camera_palm_regions #(.GW(GRID_W),.GH(GRID_H),.MIN_AREA(MIN_AREA),.MAX_AREA(MAX_AREA),.MIN_SEEDS(TRACK_FILTER ? 0 : 3),
            .PREFER_TRACK(TRACK_FILTER || IDENTITY_SELECT),.STRICT_SELECT(IDENTITY_SELECT),
            .MIN_FOREGROUND_SEEDS(SKIN_RECONSTRUCT ? 3 : 0),.MAX_ASPECT(PALM_MAX_ASPECT),.SHAPE_FEATURES(POSE_FEATURES)) analysis(
            .clk(clk),.rst(rst || recalibrate),.begin_frame(first),.end_frame(filtered_end),
            .enabled(background_ready && !scene_block),.sample_valid(filtered_valid),
            .x(filtered_x),.y(filtered_y),.dense(filtered_dense),
            .motion_seed(filtered_motion),.foreground_seed(filtered_foreground),
            .reference_valid(IDENTITY_SELECT ? selection_reference[40] : track_reference_valid),
            .reference_x(IDENTITY_SELECT ? selection_reference[39:30] : tracked_x),
            .reference_y(IDENTITY_SELECT ? selection_reference[29:20] : tracked_y),
            .reference_width(IDENTITY_SELECT ? selection_reference[19:10] : tracked_width),
            .reference_height(IDENTITY_SELECT ? selection_reference[9:0] : tracked_height),
            .done(region_done),.valid(region_valid),.overflow(region_overflow),.area(region_area),.core(region_core),.motion_count(region_motion),
            .sum_x(region_sx),.sum_y(region_sy),.min_x(region_lx),.max_x(region_hx),.min_y(region_ly),.max_y(region_hy),.shape_counts(region_shape));
    end else begin: no_regions
        assign region_done=0;assign region_valid=0;assign region_overflow=0;
        assign region_area=0;assign region_core=0;assign region_motion=0;assign region_sx=0;assign region_sy=0;
        assign region_lx=0;assign region_hx=0;assign region_ly=0;assign region_hy=0;
        assign region_shape=0;
    end endgenerate
    // Counts share the exact sampling phase and frame boundary with G and D.
    always @(posedge clk)begin
        if(rst || recalibrate)begin
            outside_left<=0;outside_right<=0;reported_left<=0;reported_right<=0;
        end else begin
            if(frame_first)begin
                outside_left<=changed && !in_roi && x_q<WIDTH/2 ? 1 : 0;
                outside_right<=changed && !in_roi && x_q>=WIDTH/2 ? 1 : 0;
            end else if(coarse_sample && changed && !in_roi)begin
                if(x_q<WIDTH/2)outside_left<=outside_left+1'b1;
                else outside_right<=outside_right+1'b1;
            end
            if(frame_last)begin reported_left<=outside_left;reported_right<=outside_right;end
        end
    end
    // The reference is one value per 8x8 display cell. Reuse its comparison
    // across that cell instead of comparing three other source pixels against
    // the top-left sample and falsely coloring stationary high-detail scenes.
    reg [GRID_W-1:0] mask_line;
    reg mask_cell;
    always @(posedge clk)begin
        if(rst || recalibrate)begin mask_line<=0;mask_cell<=0;end
        else if(de_q && x_q[2:0]==0 && y_q[2:0]==0)begin
            mask_line[x_q>>3]<=selected;mask_cell<=selected;
        end
    end
    wire cell_changed=y_q[2:0]==0 ? (x_q[2:0]==0 ? selected : mask_cell) : mask_line[x_q>>3];
    reg [18:0] sum_x,sum_y;
    reg [6:0] min_x,max_x;
    reg [5:0] min_y,max_y;
    reg [9:0] left_edge,right_edge,top_edge,bottom_edge;
    reg [9:0] pending_left,pending_right,pending_top,pending_bottom;
    // Two 19-cycle restoring dividers share their denominator. No pixel-rate
    // division and no division by zero; all sums fit a complete 80x60 grid.
    reg dividing;
    reg [4:0] division_step;
    reg [12:0] denominator;
    reg [18:0] numerator_x,numerator_y,quotient_x,quotient_y;
    reg [13:0] remainder_x,remainder_y;
    wire [13:0] trial_x={remainder_x[12:0],numerator_x[18]};
    wire [13:0] trial_y={remainder_y[12:0],numerator_y[18]};
    wire take_x=trial_x>={1'b0,denominator},take_y=trial_y>={1'b0,denominator};
    wire [18:0] next_qx={quotient_x[17:0],take_x},next_qy={quotient_y[17:0],take_y};
    always @(posedge clk)begin
        if(rst || recalibrate)begin
            area<=0;global_changed<=0;raw_area<=0;skin_area<=0;sum_x<=0;sum_y<=0;
            min_x<=127;max_x<=0;min_y<=63;max_y<=0;
            measurement_valid<=0;measurement_area<=0;measurement_x<=0;measurement_y<=0;reported_global<=0;reported_raw<=0;reported_skin<=0;reported_core<=0;rejection<=1;
            left_edge<=0;right_edge<=0;top_edge<=0;bottom_edge<=0;
            pending_left<=0;pending_right<=0;pending_top<=0;pending_bottom<=0;
            dividing<=0;division_step<=0;denominator<=0;
            numerator_x<=0;numerator_y<=0;quotient_x<=0;quotient_y<=0;remainder_x<=0;remainder_y<=0;
        end else begin
            if(frame_first)begin
                area<=fg ? 1 : 0;global_changed<=changed ? 1 : 0;sum_x<=0;sum_y<=0;
                raw_area<=raw_fg ? 1 : 0;skin_area<=(raw_fg && skin) ? 1 : 0;
                min_x<=fg ? 0 : 127;max_x<=0;min_y<=fg ? 0 : 63;max_y<=0;
            end else if(coarse_sample)begin
                if(changed)global_changed<=global_changed+1'b1;
                if(raw_fg)raw_area<=raw_area+1'b1;
                if(raw_fg && skin)skin_area<=skin_area+1'b1;
                if(fg)begin
                    area<=area+1'b1;sum_x<=sum_x+x_q[9:3];sum_y<=sum_y+y_q[8:3];
                    if(x_q[9:3]<min_x)min_x<=x_q[9:3];
                    if(x_q[9:3]>max_x)max_x<=x_q[9:3];
                    if(y_q[8:3]<min_y)min_y<=y_q[8:3];
                    if(y_q[8:3]>max_y)max_y<=y_q[8:3];
                end
            end
            if(frame_last)begin
                measurement_area<=PALM_FILTER ? 13'd0 : area;
                reported_core<=0;
                reported_global<=global_changed;
                reported_raw<=raw_area;reported_skin<=skin_area;
                rejection<=!background_ready ? 1 : scene_block ? 4 : area>MAX_AREA ? 3 : area<MIN_AREA ? 2 : 0;
                if(PALM_FILTER)begin
                    measurement_valid<=0;dividing<=0;
                    rejection<=!background_ready ? 1 : scene_block ? 4 : 6;
                end else if(background_ready && area>=MIN_AREA && area<=MAX_AREA && !scene_block)begin
                    denominator<=area;numerator_x<=sum_x;numerator_y<=sum_y;
                    quotient_x<=0;quotient_y<=0;remainder_x<=0;remainder_y<=0;
                    division_step<=0;dividing<=1;
                    pending_left<={min_x,3'b000};pending_right<={max_x,3'b111};
                    pending_top<={1'b0,min_y,3'b000};pending_bottom<={1'b0,max_y,3'b111};
                end else begin measurement_valid<=0;dividing<=0;end
            end else if(PALM_FILTER && region_done)begin
                measurement_area<=region_area;reported_core<=region_core;
                rejection<=!background_ready ? 1 : reported_scene_block ? 4 : region_overflow ? 7 : region_valid ? 0 : reported_skin<MIN_AREA ? 2 : 5;
                if(background_ready && !reported_scene_block && region_valid && !region_overflow)begin
                    denominator<=region_area;numerator_x<=region_sx;numerator_y<=region_sy;
                    quotient_x<=0;quotient_y<=0;remainder_x<=0;remainder_y<=0;
                    division_step<=0;dividing<=1;
                    pending_left<={region_lx,3'b000};pending_right<={region_hx,3'b111};
                    pending_top<={1'b0,region_ly,3'b000};pending_bottom<={1'b0,region_hy,3'b111};
                end else begin measurement_valid<=0;dividing<=0;end
            end else if(dividing)begin
                numerator_x<=numerator_x<<1;numerator_y<=numerator_y<<1;
                quotient_x<=next_qx;quotient_y<=next_qy;
                remainder_x<=take_x ? trial_x-{1'b0,denominator} : trial_x;
                remainder_y<=take_y ? trial_y-{1'b0,denominator} : trial_y;
                if(division_step==18)begin
                    dividing<=0;measurement_valid<=1;
                    measurement_x<={next_qx[6:0],3'b100};measurement_y<={1'b0,next_qy[5:0],3'b100};
                    left_edge<=pending_left;right_edge<=pending_right;top_edge<=pending_top;bottom_edge<=pending_bottom;
                end else division_step<=division_step+1'b1;
            end
        end
    end
    // Integration trial: identity association of the OLD dense-region geometry.
    // This is not the P1 distance-core estimator and not open-palm recognition.
    reg [31:0] camera_sequence,analysis_sequence;
    reg analysis_fresh,track_sample,measurement_motion;
    wire [2:0] track_reason;
    wire [3:0] association_mismatch;
    reg [12:0] tracked_area;
    reg [9:0] tracked_left,tracked_right,tracked_top,tracked_bottom;
    wire measurement_good=background_ready && !reported_scene_block && region_valid && !region_overflow;
    wire [9:0] measurement_width=right_edge-left_edge+1'b1;
    wire [9:0] measurement_height=bottom_edge-top_edge+1'b1;
    generate if(TRACK_FILTER && PALM_FILTER)begin: tracker
        camera_candidate_track #(.STALE_CYCLES(50000000),.RECOVER_FRAMES(4),.RECOVER_CYCLES(18750000)) association(
            .clk(clk),.rst(rst || !have_frame || !background_ready),.recalibrate(recalibrate),
            .sample_valid(track_sample),.frame_id(analysis_sequence),
            .candidate_valid(measurement_valid),.motion_supported(measurement_motion),.overflow(region_overflow),
            .candidate_x(measurement_x),.candidate_y(measurement_y),
            .candidate_width(measurement_width),.candidate_height(measurement_height),
            .locked(track_locked),.update(track_update),.reference_valid(track_reference_valid),.track_x(tracked_x),.track_y(tracked_y),
            .track_width(tracked_width),.track_height(tracked_height),.reason(track_reason),.association_mismatch(association_mismatch));
    end else begin: no_tracker
        assign track_locked=0;assign track_update=0;assign track_reference_valid=0;
        assign tracked_x=0;assign tracked_y=0;assign tracked_width=0;assign tracked_height=0;assign track_reason=0;assign association_mismatch=0;
    end endgenerate
    always @(posedge clk)begin
        track_sample<=0;
        if(rst || recalibrate)begin
            camera_sequence<=0;analysis_sequence<=0;analysis_fresh<=0;track_sample<=0;measurement_motion<=0;
            tracked_area<=0;tracked_left<=0;tracked_right<=0;tracked_top<=0;tracked_bottom<=0;
        end else begin
            if(fresh_frame)camera_sequence<=camera_sequence+1'b1;
            if(frame_first)begin
                analysis_fresh<=fresh_pending || fresh_frame;
                analysis_sequence<=camera_sequence+(fresh_frame ? 32'd1 : 32'd0);
            end
            if(region_done)begin
                measurement_motion<=region_motion>=3;
                if(analysis_fresh && !measurement_good)track_sample<=1;
            end
            if(dividing && division_step==18 && analysis_fresh)track_sample<=1;
            if(track_update)begin
                tracked_area<=measurement_area;
                tracked_left<=left_edge;tracked_right<=right_edge;
                tracked_top<=top_edge;tracked_bottom<=bottom_edge;
            end
        end
    end
    assign target_valid=TRACK_FILTER ? track_locked : measurement_valid;
    assign centroid_x=TRACK_FILTER ? tracked_x : measurement_x;
    assign centroid_y=TRACK_FILTER ? tracked_y : measurement_y;
    assign target_area=TRACK_FILTER ? (track_locked ? tracked_area : 13'd0) : measurement_area;
    wire [9:0] show_left=TRACK_FILTER ? tracked_left : left_edge;
    wire [9:0] show_right=TRACK_FILTER ? tracked_right : right_edge;
    wire [9:0] show_top=TRACK_FILTER ? tracked_top : top_edge;
    wire [9:0] show_bottom=TRACK_FILTER ? tracked_bottom : bottom_edge;
    wire roi_border=in_roi && (x_q==ROI_X0 || x_q==ROI_X1-1 || y_q==ROI_Y0 || y_q==ROI_Y1-1);
    wire box_border=target_valid && x_q>=show_left && x_q<=show_right && y_q>=show_top && y_q<=show_bottom &&
        (x_q==show_left || x_q==show_right || y_q==show_top || y_q==show_bottom);
    wire crosshair=target_valid && ((y_q==centroid_y && x_q+4>=centroid_x && x_q<=centroid_x+4) ||
        (x_q==centroid_x && y_q+4>=centroid_y && y_q<=centroid_y+4));
    assign out_de=de_q;assign out_hs=hs_q;assign out_vs=vs_q;
    // Raw segmented foreground remains visible before/without track lock.
    // Cyan thin box: current accepted region; yellow box/red cross: track.
    wire current_border=PALM_FILTER && measurement_valid && x_q>=left_edge && x_q<=right_edge &&
        y_q>=top_edge && y_q<=bottom_edge &&
        (x_q==left_edge || x_q==right_edge || y_q==top_edge || y_q==bottom_edge);
    reg [24:0] diagnostic_second;
    reg [7:0] fresh_count,update_count,fresh_rate,update_rate;
    wire diagnostic_fresh=SOURCE_MODE ? track_sample : fresh_frame;
    always @(posedge clk)begin
        if(rst || recalibrate)begin
            diagnostic_second<=0;fresh_count<=0;update_count<=0;fresh_rate<=0;update_rate<=0;
        end else if(diagnostic_second==24999999)begin
            diagnostic_second<=0;
            fresh_rate<=fresh_count==255 ? 8'd255 : fresh_count+diagnostic_fresh;
            update_rate<=update_count==255 ? 8'd255 : update_count+track_update;
            fresh_count<=0;update_count<=0;
        end else begin
            diagnostic_second<=diagnostic_second+1'b1;
            if(diagnostic_fresh && fresh_count!=255)fresh_count<=fresh_count+1'b1;
            if(track_update && update_count!=255)update_count<=update_count+1'b1;
        end
    end
    wire [23:0] marked_rgb=!de_q ? 24'd0 : (x_q<16 && y_q<16) ?
        (background_ready ? 24'h00ff00 : (capturing || candidate_valid) ? 24'h00ffff : 24'hffff00) :
        crosshair ? 24'hff0000 : box_border ? 24'hffff00 : (current_border || roi_border) ? 24'h00ffff :
        (background_ready && de_q && in_roi && cell_changed) ? ((rgb_q & 24'h7f7f7f)+24'h008000) : rgb_q;
    assign processing_done=track_sample;
    assign pose_sample=track_sample;
    assign pose_id=analysis_sequence;assign pose_counts=region_shape;assign pose_area=measurement_area;
    assign pose_valid=measurement_valid && background_ready && !reported_scene_block && !region_overflow;
    assign pose_edges={bottom_edge>=ROI_Y1-1,top_edge<=ROI_Y0,right_edge>=ROI_X1-1,left_edge<=ROI_X0};
    assign pose_clipped=|pose_edges;
    assign mask_valid=filtered_valid;
    assign mask_x=filtered_x;assign mask_y=filtered_y;
    assign mask_bits=BINARY_FILTER!=0 ? {filtered_foreground,filtered_dense,filtered_foreground} : {raw_fg && background_ready,skin && in_roi,fg && background_ready};
    assign analysis_status={scene_left,scene_right,background_ready,target_area,reported_global,reported_raw,reported_skin,reported_core,
        rejection,stable_count,track_reason,track_locked,measurement_valid,association_mismatch,fresh_rate,update_rate,
        show_left,show_right,show_top,show_bottom,centroid_x,centroid_y,left_edge,right_edge,top_edge,bottom_edge};
    camera_foreground_overlay info(.de(de_q),.x(x_q),.y(y_q),.base_rgb(marked_rgb),.area(target_area),
        .global_changed(reported_global),.raw_area(reported_raw),.skin_area(reported_skin),
        .rejection(rejection),.stable_count(stable_count),.core_area(reported_core),
        .track_reason(track_reason),.track_locked(track_locked),.current_valid(measurement_valid),
        .diagnostics_enabled(TRACK_FILTER!=0),
        .scene_diagnostics(SPATIAL_SCENE_GATE!=0),.scene_left(scene_left),.scene_right(scene_right),
        .pipeline_rates(pipeline_rates),.pipeline_rates_valid(pipeline_rates_valid),.association_mismatch(association_mismatch),
        .fresh_rate(fresh_rate),.update_rate(update_rate),.rgb(out_rgb));
endmodule

module camera_background_button #(parameter integer DEBOUNCE_CYCLES=125000)(
    input wire clk,rst,key_n,output reg pulse);
    (* async_reg="true" *) reg [1:0] key_sync;
    localparam CW=DEBOUNCE_CYCLES>1 ? $clog2(DEBOUNCE_CYCLES) : 1;
    reg [CW-1:0] count;
    reg stable;
    always @(posedge clk)begin
        pulse<=0;
        if(rst)begin key_sync<=3;stable<=1;count<=0;pulse<=0;end
        else begin
            key_sync<={key_sync[0],key_n};
            if(key_sync[1]==stable)count<=0;
            else if(count==DEBOUNCE_CYCLES-1)begin
                stable<=key_sync[1];count<=0;
                if(!key_sync[1])pulse<=1;
            end else count<=count+1'b1;
        end
    end
endmodule

// Raster 3x3 center-preserving filter. Two 3-bit line shifts retain aligned seeds.
// Sparse samples require at least one idle clock after a line's last cell.
// Right padding uses that idle clock; bottom padding drains after end_frame.
module camera_binary_denoise #(parameter GW=80,GH=60,THRESHOLD=5)(
 input clk,rst,begin_frame,end_frame,sample_valid,input [6:0] x,input [5:0] y,input [2:0] data,
 output reg out_valid,out_end,output reg [6:0] out_x,output reg [5:0] out_y,output reg [2:0] out_data);
 reg [GW*3-1:0] line1,line2;
 reg [2:0] a0,a1,b0,b1,c0,c1;
 reg right_pending,draining,drain_gap,finish_pending;
 reg [6:0] drain_x;reg [5:0] right_y;reg [2:0] right_data;
 wire take=sample_valid || (draining && !drain_gap);
 wire [6:0] ix=draining ? drain_x : x;
 wire [6:0] iy=draining ? GH : {1'b0,y};
 wire [2:0] bottom=draining ? 3'b000 : data;
 wire [2:0] middle=iy>=1 ? line1[2:0] : 3'b000;
 wire [2:0] top=iy>=2 ? line2[2:0] : 3'b000;
 wire [3:0] neighbors={3'b0,a0[0]}+a1[0]+top[0]+b0[0]+middle[0]+c0[0]+c1[0]+bottom[0];
 wire keep=b1[0] && neighbors>=THRESHOLD;
 wire [3:0] right_neighbors={3'b0,a1[0]}+top[0]+b1[0]+c1[0]+bottom[0];
 wire right_keep=middle[0] && right_neighbors>=THRESHOLD;
 always @(posedge clk)begin
 out_valid<=0;out_end<=0;
 if(rst || begin_frame)begin
  line1<=0;line2<=0;a0<=0;a1<=0;b0<=0;b1<=0;c0<=0;c1<=0;
  right_pending<=0;draining<=0;drain_gap<=0;finish_pending<=0;drain_x<=0;
  right_y<=0;right_data<=0;out_x<=0;out_y<=0;out_data<=0;
 end else begin
  if(right_pending)begin out_valid<=1;out_x<=GW-1;out_y<=right_y;out_data<=right_data;right_pending<=0;end
  if(finish_pending && !right_pending)begin out_end<=1;finish_pending<=0;end
  if(end_frame)begin draining<=1;drain_x<=0;drain_gap<=0;end
  if(draining)begin
   drain_gap<=!drain_gap;
   if(!drain_gap)begin
    if(drain_x==GW-1)begin draining<=0;finish_pending<=1;end
    else drain_x<=drain_x+1'b1;
   end
  end
  if(take)begin
   line1<={bottom,line1[GW*3-1:3]};line2<={line1[2:0],line2[GW*3-1:3]};
   if(ix==0)begin a0<=0;a1<=top;b0<=0;b1<=middle;c0<=0;c1<=bottom;end
   else begin
    a0<=a1;a1<=top;b0<=b1;b1<=middle;c0<=c1;c1<=bottom;
    if(iy>=1)begin out_valid<=1;out_x<=ix-1'b1;out_y<=iy-1'b1;out_data<={b1[2:1]&{2{keep}},keep};end
   end
   if(ix==GW-1 && iy>=1)begin
    right_pending<=1;right_y<=iy-1'b1;right_data<={middle[2:1]&{2{right_keep}},right_keep};
   end
  end
 end
 end
endmodule

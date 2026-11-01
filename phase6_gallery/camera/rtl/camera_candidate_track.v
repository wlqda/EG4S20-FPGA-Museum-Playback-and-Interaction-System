// P1 single-candidate association. NOT a hand/open-palm classifier.
// One completed, uniquely numbered camera-frame result per sample_valid.
// Upstream must supply dense geometry and mark bad/overflow results invalid.
module camera_candidate_track #(
    parameter integer ACQUIRE_FRAMES=3, MISS_FRAMES=3,
    parameter integer STALE_CYCLES=12500000, MARGIN=8,
    parameter integer RECOVER_FRAMES=0, RECOVER_CYCLES=6250000
)(
    input wire clk,rst,recalibrate,sample_valid,
    input wire [31:0] frame_id,
    input wire candidate_valid,motion_supported,overflow,
    input wire [9:0] candidate_x,candidate_y,candidate_width,candidate_height,
    output reg locked,output reg update,output wire reference_valid,
    output reg [9:0] track_x,track_y,track_width,track_height,
    output reg [2:0] reason,output reg [3:0] association_mismatch
);
    localparam CW=STALE_CYCLES>1 ? $clog2(STALE_CYCLES) : 1;
    localparam AW=ACQUIRE_FRAMES>1 ? $clog2(ACQUIRE_FRAMES+1) : 1;
    localparam MW=MISS_FRAMES>1 ? $clog2(MISS_FRAMES+1) : 1;
    reg [CW-1:0] stale;
    reg [AW-1:0] confirmation;
    reg [MW-1:0] misses;
    reg have_id;
    reg [31:0] last_id;
    localparam RW=RECOVER_FRAMES>0 ? $clog2(RECOVER_FRAMES+1) : 1;
    localparam RTW=RECOVER_CYCLES>1 ? $clog2(RECOVER_CYCLES) : 1;
    reg [RW-1:0] recovery_left;
    reg [RTW-1:0] recovery_age;
    reg recovery_match;
    assign reference_valid=locked || recovery_left!=0;
    // Serial-number ordering permits wrap but rejects duplicate/older results.
    // Forward gaps must be less than 2^31; reset/recalibrate on stream restart.
    wire [31:0] frame_delta=frame_id-last_id;
    wire new_result=sample_valid && (!have_id ||
        (frame_delta!=0 && !frame_delta[31]));
    wire [9:0] dx=candidate_x>=track_x ? candidate_x-track_x : track_x-candidate_x;
    wire [9:0] dy=candidate_y>=track_y ? candidate_y-track_y : track_y-candidate_y;
    wire geometry_ok=candidate_valid && candidate_width>=4 && candidate_height>=4;
    // Widen arithmetic: 2*width must not wrap at a 10-bit boundary.
    wire x_ok={1'b0,dx}<=({1'b0,track_width}>>1)+MARGIN;
    wire y_ok={1'b0,dy}<=({1'b0,track_height}>>1)+MARGIN;
    wire width_ok={candidate_width,1'b0}>={1'b0,track_width} && {1'b0,candidate_width}<={track_width,1'b0};
    wire height_ok={candidate_height,1'b0}>={1'b0,track_height} && {1'b0,candidate_height}<={track_height,1'b0};
    wire associated=geometry_ok && x_ok && y_ok && width_ok && height_ok;
    // reason: 0 accepted, 1 search/confirm, 2 missing, 3 association,
    // 4 overflow, 5 stale stream, 6 bounded recovery.
    // Only locked+update is fresh geometry.
    always @(posedge clk)begin
        update<=0;
        if(rst || recalibrate)begin
            locked<=0;update<=0;track_x<=0;track_y<=0;track_width<=0;track_height<=0;
            stale<=0;confirmation<=0;misses<=0;have_id<=0;last_id<=0;reason<=1;
            recovery_left<=0;recovery_age<=0;recovery_match<=0;association_mismatch<=0;
        end else if(stale==STALE_CYCLES-1)begin
            // Timeout wins over a result arriving at the deadline. A later new
            // frame must reacquire; repeating an old frame cannot revive it.
            locked<=0;confirmation<=0;misses<=0;reason<=5;association_mismatch<=0;
            recovery_left<=0;recovery_age<=0;recovery_match<=0;
            if(new_result)begin last_id<=frame_id;have_id<=1;stale<=0;end
        end else begin
            stale<=stale+1'b1;
            // A bounded remembered target is not a visible/fresh track.
            // Duplicate results cannot extend either recovery deadline.
            if(recovery_left!=0)begin
                if(recovery_age==RECOVER_CYCLES-1)begin
                    recovery_left<=0;recovery_match<=0;
                end else recovery_age<=recovery_age+1'b1;
            end
            if(new_result)begin
                last_id<=frame_id;have_id<=1;stale<=0;
                association_mismatch<=geometry_ok && !overflow && reference_valid ?
                    {!height_ok,!width_ok,!y_ok,!x_ok} : 4'b0;
                if(overflow)begin
                    locked<=0;confirmation<=0;misses<=0;reason<=4;
                    recovery_left<=0;recovery_match<=0;
                end else if(locked)begin
                    if(associated)begin
                        track_x<=candidate_x;track_y<=candidate_y;
                        track_width<=candidate_width;track_height<=candidate_height;
                        misses<=0;update<=1;reason<=0;
                    end else begin
                        reason<=geometry_ok ? 3 : 2;
                        if(misses==MISS_FRAMES-1)begin
                            locked<=0;confirmation<=0;misses<=0;
                            recovery_left<=RECOVER_FRAMES;recovery_age<=0;recovery_match<=0;
                        end
                        else misses<=misses+1'b1;
                    end
                end else if(recovery_left!=0)begin
                    // Two consecutive fresh, valid matches to the retained
                    // geometry restore a track without renewed motion.
                    // Do not move the reference while confirming recovery.
                    reason<=6;
                    recovery_left<=recovery_left-1'b1;
                    recovery_match<=associated;
                    if(recovery_age==RECOVER_CYCLES-1)begin
                        recovery_left<=0;recovery_match<=0;
                    end else if(associated && recovery_match)begin
                        locked<=1;update<=1;reason<=0;misses<=0;confirmation<=0;
                        track_x<=candidate_x;track_y<=candidate_y;
                        track_width<=candidate_width;track_height<=candidate_height;
                        recovery_left<=0;recovery_match<=0;
                    end
                end else if(geometry_ok && ((confirmation==0 && motion_supported) || (confirmation!=0 && associated)))begin
                    track_x<=candidate_x;track_y<=candidate_y;
                    track_width<=candidate_width;track_height<=candidate_height;
                    misses<=0;
                    if(confirmation==ACQUIRE_FRAMES-1)begin
                        locked<=1;confirmation<=0;update<=1;reason<=0;
                    end else begin confirmation<=confirmation+1'b1;reason<=1;end
                end else begin confirmation<=0;reason<=1;end
            end
        end
    end
endmodule

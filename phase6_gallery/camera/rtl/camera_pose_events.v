// One action per neutral -> direction excursion, driven by new source results.
// Labels: 0 unknown, 1 neutral, 2 left, 3 right, 4 up, 5 down.
module camera_pose_events #(
    parameter integer NEUTRAL_FRAMES=3,DIRECTION_FRAMES=2,STALE_CYCLES=12500000,
    parameter integer UNCERTAIN_CYCLES=18750000,EXCURSION_CYCLES=50000000
)(input wire clk,rst,enabled,cancel,sample_valid,input wire [31:0] frame_id,
  input wire [2:0] label,output reg armed,output reg event_valid,
  output reg [2:0] event_direction,output reg [31:0] event_sequence);
    reg have_id;reg [31:0] last_id;
    reg [23:0] age;reg [3:0] neutral_count,direction_count;reg [2:0] direction;
    reg uncertain;reg [24:0] uncertain_age;reg [25:0] excursion_age;
    wire [31:0] delta=frame_id-last_id;
    wire fresh=sample_valid && (!have_id || (delta!=0 && !delta[31]));
    always @(posedge clk)begin
        event_valid<=0;
        if(rst)begin
            have_id<=0;last_id<=0;age<=0;armed<=0;event_valid<=0;event_direction<=0;event_sequence<=0;
            neutral_count<=0;direction_count<=0;direction<=0;
            uncertain<=0;uncertain_age<=0;excursion_age<=0;
        end else begin
            if(age<STALE_CYCLES)age<=age+1'b1;
            if(fresh)begin have_id<=1;last_id<=frame_id;age<=0;end
            if(uncertain && uncertain_age<UNCERTAIN_CYCLES)uncertain_age<=uncertain_age+1'b1;
            if(armed && excursion_age<EXCURSION_CYCLES)excursion_age<=excursion_age+1'b1;
            if(!enabled || cancel || (age>=STALE_CYCLES-1 && !fresh) ||
               (uncertain && uncertain_age>=UNCERTAIN_CYCLES-1) || excursion_age>=EXCURSION_CYCLES-1)begin
                armed<=0;neutral_count<=0;direction_count<=0;direction<=0;
                uncertain<=0;uncertain_age<=0;excursion_age<=0;
                if(!enabled || cancel)age<=0;
                if(!enabled)begin have_id<=0;last_id<=0;end
            end else if(fresh)begin
                // Valid but ambiguous transition frames cannot vote. A bounded
                // grace period lets fingers travel between distinct templates.
                // Lost/clipped candidates use cancel and disarm immediately.
                if(label==0)begin
                    neutral_count<=0;direction_count<=0;direction<=0;
                    if(!uncertain)begin uncertain<=1;uncertain_age<=0;end
                end else if(label>5)begin armed<=0;neutral_count<=0;direction_count<=0;direction<=0;end
                else if(label==1)begin
                    uncertain<=0;uncertain_age<=0;excursion_age<=0;
                    direction_count<=0;direction<=0;
                    if(neutral_count<NEUTRAL_FRAMES)neutral_count<=neutral_count+1'b1;
                    if(neutral_count>=NEUTRAL_FRAMES-1)armed<=1;
                end else begin
                    uncertain<=0;uncertain_age<=0;
                    neutral_count<=0;
                    if(armed)begin
                        direction<=label;
                        if(direction==label)direction_count<=direction_count+1'b1;
                        else direction_count<=1;
                        if((direction==label && direction_count>=DIRECTION_FRAMES-1) || DIRECTION_FRAMES==1)begin
                            event_valid<=1;event_direction<=label;event_sequence<=event_sequence+1'b1;
                            armed<=0;direction_count<=0;direction<=0;
                        end
                    end
                end
            end
        end
    end
endmodule

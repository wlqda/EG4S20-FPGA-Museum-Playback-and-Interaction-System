// Coarse RGB/luminance hand candidate filter, not a semantic hand classifier.
// Temporal memory advances ONLY on newly displayed camera frames.
module camera_hand_candidate #(
    parameter integer WIDTH=640,HEIGHT=480,GRID_W=WIDTH/8,PIXELS=GRID_W*(HEIGHT/8),AW=$clog2(PIXELS),
    parameter integer MOTION_THRESHOLD=10,HOLD_FRAMES=3
)(input wire clk,rst,recalibrate,fresh_frame,de,
  input wire [9:0] x,y,input wire [23:0] rgb,
  input wire changed,output wire skin,eligible);
    (* ram_style="bram_9k" *) reg [7:0] previous[0:PIXELS-1];
    (* ram_style="bram_9k" *) reg [7:0] activity[0:PIXELS-1];
    reg [7:0] previous_q,activity_q,grey_q;
    reg [23:0] rgb_q;
    reg [AW-1:0] address_q;
    reg sample_q,fresh_pending,fresh_current,previous_valid;
    wire first=de && x==0 && y==0;
    wire last=de && x==WIDTH-1 && y==HEIGHT-1;
    wire [AW-1:0] address=de ? (y>>3)*GRID_W+(x>>3) : {AW{1'b0}};
    wire [9:0] weighted={2'b0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'b0,rgb[7:0]};
    wire [7:0] delta=grey_q>=previous_q ? grey_q-previous_q : previous_q-grey_q;
    wire [7:0] red=rgb_q[23:16],green=rgb_q[15:8],blue=rgb_q[7:0];
    assign skin=red>40 && green>20 && blue>10 && {1'b0,red}>={1'b0,green}+9'd4 &&
        {1'b0,red}>={1'b0,blue}+9'd8 && red-blue>12;
    wire moving=previous_valid && delta>=MOTION_THRESHOLD;
    assign eligible=skin && previous_valid && (moving || activity_q!=0);
    wire [7:0] next_activity=(!previous_valid || !changed || !skin) ? 8'd0 :
        moving ? HOLD_FRAMES : activity_q!=0 ? activity_q-1'b1 : 8'd0;
    // Delayed writes ensure the sampled cell sees its OLD previous-frame value
    // before any write to that address; subsequent pixels are not sampled.
    always @(posedge clk)begin
        previous_q<=previous[address];activity_q<=activity[address];
        if(!rst && !recalibrate && sample_q && fresh_current)begin
            previous[address_q]<=grey_q;activity[address_q]<=next_activity;
        end
    end
    always @(posedge clk)begin
        if(rst || recalibrate)begin
            rgb_q<=0;grey_q<=0;sample_q<=0;address_q<=0;
            fresh_pending<=0;fresh_current<=0;previous_valid<=0;
        end else begin
            rgb_q<=rgb;grey_q<=weighted[9:2];address_q<=address;
            sample_q<=de && x[2:0]==0 && y[2:0]==0;
            if(fresh_frame)fresh_pending<=1;
            if(first)begin fresh_current<=fresh_pending || fresh_frame;fresh_pending<=0;end
            if(last && fresh_current)previous_valid<=1;
        end
    end
endmodule

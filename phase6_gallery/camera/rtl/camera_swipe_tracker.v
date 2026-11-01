// S2: register-only endpoint trajectory recognition. Coordinates are image coordinates:
// x grows right, y grows down. No joint model or semantic palm guarantee.
module camera_swipe_tracker #(
 parameter integer STABLE_FRAMES=3, MOTION_FRAMES=2, SETTLE_FRAMES=2,
 parameter integer STALE_CYCLES=15000000, TRACK_CYCLES=62500000,
 parameter integer ARM_CYCLES=75000000, MIRROR_X=0
)(
 input wire clk,rst,enabled,restart,epoch_reset,sample_valid,candidate_valid,clipped,
 input wire [31:0] frame_id,input wire [3:0] edges,
 input wire [9:0] cx,cy,width,height,
 output reg [2:0] state,reason,direction,
 output wire armed,output reg event_valid,output reg [2:0] event_direction,
 output reg [31:0] event_sequence,
 output reg [9:0] origin_x,origin_y,
 output reg target_visible
);
 localparam SEARCH=0,CONFIRM=1,ARMED=2,TRACK=3,RETURN=4;
 reg have_id;reg [31:0] last_id;
 reg [26:0] age,elapsed;
 reg [7:0] stable,moving;
 reg [9:0] last_x,last_y,ref_w,ref_h,threshold;
 reg [11:0] travel_x,travel_y;reg [3:0] wrist_edges;reg [7:0] settled;
 wire [31:0] id_delta=frame_id-last_id;
 wire fresh=sample_valid && (!have_id || (id_delta!=0 && !id_delta[31]));
 wire center=cx>=256 && cx<=384 && cy>=184 && cy<=296;
 wire geometry=width>=48 && height>=48 && width<=320 && height<=320;
 wire single_edge=edges!=0 && (edges & (edges-1'b1))==0;
 wire learning=state==SEARCH || state==RETURN;
 wire clip_ok=!clipped || (learning ? single_edge : edges!=0 && (edges & ~wrist_edges)==0);
 wire good=candidate_valid && clip_ok && geometry;
 wire [9:0] dx=cx>=origin_x ? cx-origin_x : origin_x-cx;
 wire [9:0] dy=cy>=origin_y ? cy-origin_y : origin_y-cy;
 wire [9:0] sx=cx>=last_x ? cx-last_x : last_x-cx;
 wire [9:0] sy=cy>=last_y ? cy-last_y : last_y-cy;
 wire [10:0] step_limit=({1'b0,ref_w}+{1'b0,ref_h})/4+24;
 wire associated=sx<=step_limit && sy<=step_limit &&
    {1'b0,width}*2>=ref_w && width<=({1'b0,ref_w}*2) &&
    {1'b0,height}*2>=ref_h && height<=({1'b0,ref_h}*2);
 // Decide from the endpoint, not from the first off-axis movement.
 wire horizontal=dx>=dy+11'd16 && {1'b0,dx,1'b0}>={1'b0,dy}+{dy,1'b0};
 wire vertical=dy>=dx+11'd16 && {1'b0,dy,1'b0}>={1'b0,dx}+{dx,1'b0};
 wire [2:0] proposed=horizontal ? (cx<origin_x ? 2 : 3) : vertical ? (cy<origin_y ? 4 : 5) : 0;
 wire [9:0] progress=horizontal ? dx : dy;
 wire [12:0] path=horizontal ? {1'b0,travel_x}+sx : {1'b0,travel_y}+sy;
 wire efficient={2'b0,progress,1'b0}>=path;
 wire quiet=sx<=12 && sy<=12;
 wire [9:0] small_side=width<height ? width : height;
 wire [9:0] new_threshold=small_side/2<48 ? 48 : small_side/2>80 ? 80 : small_side/2;
 assign armed=state==ARMED || state==TRACK;
 always @(posedge clk)begin
  event_valid<=0;
  if(rst)begin
   state<=SEARCH;reason<=0;direction<=0;event_direction<=0;event_sequence<=0;
   have_id<=0;last_id<=0;age<=0;elapsed<=0;stable<=0;moving<=0;travel_x<=0;travel_y<=0;settled<=0;wrist_edges<=0;
   origin_x<=320;origin_y<=240;last_x<=320;last_y<=240;ref_w<=0;ref_h<=0;threshold<=48;target_visible<=0;
  end else begin
   // IDs stay monotonic across disable/restart; duplicate frames cannot arm.
   if(fresh)begin have_id<=1;last_id<=frame_id;age<=0;target_visible<=good;end
   else if(age<STALE_CYCLES)age<=age+1'b1;
   if(elapsed<ARM_CYCLES)elapsed<=elapsed+1'b1;
   if(epoch_reset)begin
    have_id<=0;age<=0;state<=SEARCH;stable<=0;moving<=0;settled<=0;direction<=0;
    reason<=0;elapsed<=0;target_visible<=0;
   end else if(!enabled || restart)begin
    state<=SEARCH;stable<=0;moving<=0;settled<=0;direction<=0;reason<=0;elapsed<=0;
   end else if(age>=STALE_CYCLES-1)begin
    state<=RETURN;stable<=0;moving<=0;settled<=0;direction<=0;reason<=4;target_visible<=0;
   end else if(state==TRACK && elapsed>=TRACK_CYCLES-1)begin
    state<=RETURN;stable<=0;moving<=0;settled<=0;direction<=0;reason<=5;
   end else if(fresh)begin
    if(!good)begin
     if(state!=SEARCH)state<=RETURN;
     stable<=0;moving<=0;settled<=0;direction<=0;reason<=!clip_ok ? 2 : 1;
    end else if(state==SEARCH || state==RETURN)begin
     if(center)begin
      state<=CONFIRM;stable<=1;origin_x<=cx;origin_y<=cy;last_x<=cx;last_y<=cy;
      ref_w<=width;ref_h<=height;threshold<=new_threshold;wrist_edges<=edges;direction<=0;reason<=0;
     end else reason<=6;
    end else if(state==CONFIRM)begin
     if(!center || dx>16 || dy>16 || !associated)begin
      state<=center ? CONFIRM : RETURN;stable<=center ? 1 : 0;reason<=3;
      origin_x<=cx;origin_y<=cy;last_x<=cx;last_y<=cy;
      ref_w<=width;ref_h<=height;threshold<=new_threshold;wrist_edges<=edges;
     end else begin
      stable<=stable+1'b1;last_x<=cx;last_y<=cy;
      if(stable>=STABLE_FRAMES-1)begin state<=ARMED;elapsed<=0;moving<=0;travel_x<=0;travel_y<=0;settled<=0;end
     end
    end else if(!associated)begin
     state<=RETURN;stable<=0;moving<=0;settled<=0;direction<=0;reason<=3;
    end else begin
     last_x<=cx;last_y<=cy;
     if(state==ARMED && (dx>=16 || dy>=16))begin
      state<=TRACK;direction<=0;moving<=1;travel_x<=dx;travel_y<=dy;settled<=0;elapsed<=0;
     end else if(state==TRACK)begin
      direction<=proposed;
      if(travel_x<3000)travel_x<=travel_x+sx;
      if(travel_y<3000)travel_y<=travel_y+sy;
      if(sx>=16 || sy>=16)begin if(moving<255)moving<=moving+1'b1;end
      if(quiet)begin if(settled<255)settled<=settled+1'b1;end else settled<=0;
      if(dx<16 && dy<16)begin
       state<=RETURN;stable<=0;settled<=0;reason<=7;
      end else if(quiet && settled>=SETTLE_FRAMES-1)begin
       if(proposed!=0 && progress>=threshold && efficient && moving>=MOTION_FRAMES)begin
        event_valid<=1;event_direction<=MIRROR_X && proposed==2 ? 3 : MIRROR_X && proposed==3 ? 2 : proposed;
        event_sequence<=event_sequence+1'b1;state<=RETURN;stable<=0;reason<=0;
       end else if(dx>=threshold || dy>=threshold)begin
        state<=RETURN;stable<=0;reason<=7;
       end
      end
     end
    end
   end
  end
 end
endmodule

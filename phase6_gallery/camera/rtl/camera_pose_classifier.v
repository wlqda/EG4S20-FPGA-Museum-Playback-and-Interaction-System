// Personal, on-board supervised calibration. No built-in hand templates.
// Selected-component 4x4 histogram, fixed axes; all feature math is serial.
module camera_pose_classifier #(
 parameter integer ACCEPT_DISTANCE=48,CLASS_MARGIN=16,MIN_SEPARATION=48,CAL_JITTER=32,
 parameter integer STALE_CYCLES=12500000,UNCERTAIN_CYCLES=18750000,EXCURSION_CYCLES=50000000,
 parameter ALLOW_WRIST_EDGE=0
)(input wire clk,rst,clear_models,enabled,capture,
 input wire sample_valid,candidate_valid,clipped,input wire [31:0] frame_id,
 input wire [3:0] edges,input wire [143:0] counts,input wire [12:0] area,
 output reg model_ready,output reg [2:0] stage,output reg collecting,
 output reg [2:0] error,output reg [2:0] pose,output reg pose_valid,
 output wire armed,event_valid,output wire [2:0] event_direction,
 output wire [31:0] event_sequence,output reg [12:0] best_distance);
 localparam IDLE=0,N_INIT=1,N_STEP=2,N_STORE=3,CAL_INIT=4,CAL_WAIT=5,CAL_ACC=6,
  CAL_DECIDE=7,C_WRITE_WAIT=8,C_WRITE=9,R_ADDR=10,R_WAIT=11,R_ACC=12,DECIDE=13,
  WRITE_WAIT=14,WRITE=15;
 reg [3:0] state,bin;
 reg [143:0] source_counts;reg [12:0] source_area;reg [31:0] source_id;
 reg [3:0] source_edges,last_edges,wrist_edges;
 reg [5:0] trained;reg [2:0] template_index;
 wire one_edge=edges!=0 && (edges & (edges-1'b1))==0;
 // N0 can learn ONE forearm-entry edge. Additional contacts are rejected.
 // This is a placement guard, not automatic wrist localization.
 wire edge_allowed=ALLOW_WRIST_EDGE && clipped && edges!=0 &&
  ((stage==0 && collecting) ? one_edge : (trained[0] && (edges & ~wrist_edges)==0));
 wire bad_clip=clipped && !edge_allowed;
 reg [1:0] cal_count;reg [14:0] cal_area_sum;reg [12:0] cal_distance,candidate_area;
 reg cal_restart,cal_finishing,training_compare;
 // One synchronous 16x34 RAM holds vector, previous sample, sum and mean.
 // No reset is required: cal_count guards previous/sum, trained guards models.
 (* ram_style="bram_32k" *) reg [33:0] feature_ram[0:15];reg [33:0] feature_q;
 wire [7:0] current_feature=feature_q[7:0],previous=feature_q[15:8];
 wire [9:0] prior_sum=feature_q[25:16];wire [7:0] mean=feature_q[33:26];
 wire [7:0] feature=training_compare ? mean : current_feature;
 wire [8:0] cal_delta=current_feature>=previous ? current_feature-previous : previous-current_feature;
 wire [10:0] average_sum={1'b0,prior_sum}+current_feature+1'b1;
 wire [7:0] next_mean=cal_finishing ? average_sum/3 : mean;
 wire [9:0] next_sum=cal_restart ? {2'b0,current_feature} : prior_sum+current_feature;
 reg [16:0] numerator,quotient;reg [13:0] remainder;reg [4:0] step;
 wire [13:0] trial={remainder[12:0],numerator[16]};
 wire take=trial>={1'b0,source_area};wire [16:0] next_q={quotient[15:0],take};
 wire feature_write=state==N_STORE || state==C_WRITE;
 wire [33:0] feature_data=state==N_STORE ? {feature_q[33:8],quotient[7:0]} :
  {next_mean,next_sum,current_feature,current_feature};
 always @(posedge clk)begin
  feature_q<=feature_ram[bin];
  if(!rst && !clear_models && enabled && !capture && feature_write)begin
   feature_ram[bin]<=feature_data;feature_q<=feature_data;
  end
 end
 (* ram_style="bram_9k" *) reg [7:0] templates[0:95];reg [12:0] template_area[0:5];reg [7:0] template_q;
 // Second neutral in a tiny second read bank. Its per-bin envelope with N0
 // reserves intermediate palm-roll appearances for NEUTRAL, never navigation.
 (* ram_style="bram_9k" *) reg [7:0] neutral1[0:15];reg [7:0] neutral1_q;
 reg [12:0] envelope_sum,envelope_distance;
 wire [7:0] neutral_lo=template_q<neutral1_q ? template_q : neutral1_q;
 wire [7:0] neutral_hi=template_q>neutral1_q ? template_q : neutral1_q;
 wire [8:0] envelope_delta=feature<neutral_lo ? neutral_lo-feature : feature>neutral_hi ? feature-neutral_hi : 9'd0;
 reg [12:0] distance_sum,distances[0:5];
 wire [6:0] read_address={template_index,4'b0}+bin;
 always @(posedge clk)begin
  template_q<=templates[read_address];
  neutral1_q<=neutral1[bin];
  if(!rst && !clear_models && enabled && !capture && state==WRITE)
   templates[{stage,4'b0}+bin]<=mean;
  if(!rst && !clear_models && enabled && !capture && state==WRITE && stage==1)neutral1[bin]<=mean;
 end
 wire [8:0] template_delta=feature>=template_q ? feature-template_q : template_q-feature;
 reg have_id;reg [31:0] last_id;reg [23:0] age;
 wire [31:0] frame_delta=frame_id-last_id;
 wire fresh=sample_valid && (!have_id || (frame_delta!=0 && !frame_delta[31]));
 reg decision_sample;reg [31:0] decision_id;reg [2:0] decision_label;
 wire cancel_events=capture || !enabled || (fresh && (!candidate_valid || bad_clip || state!=IDLE));
 camera_pose_events #(.STALE_CYCLES(STALE_CYCLES),.UNCERTAIN_CYCLES(UNCERTAIN_CYCLES),.EXCURSION_CYCLES(EXCURSION_CYCLES)) events(
  .clk(clk),.rst(rst || clear_models),.enabled(enabled && model_ready),.cancel(cancel_events),
  .sample_valid(decision_sample),.frame_id(decision_id),.label(decision_label),
  .armed(armed),.event_valid(event_valid),.event_direction(event_direction),.event_sequence(event_sequence));
 integer i;reg [12:0] ranked_best,ranked_second,rank_distance,min_cross,neutral_distance;
 reg [2:0] ranked_label,winning_template;
 always @*begin
  ranked_best=8191;ranked_second=8191;ranked_label=0;winning_template=0;
  neutral_distance=distances[0]<distances[1] ? distances[0] : distances[1];
  if(envelope_distance<neutral_distance)neutral_distance=envelope_distance;
  for(integer k=1;k<=5;k=k+1)begin
   rank_distance=k==1 ? neutral_distance : distances[k];
   if(rank_distance<ranked_best)begin
    ranked_second=ranked_best;ranked_best=rank_distance;ranked_label=k;
    winning_template=k==1 ? (distances[0]<distances[1] ? 0 : 1) : k;
   end else if(rank_distance<ranked_second)ranked_second=rank_distance;
  end
  min_cross=8191;
  for(integer k=0;k<6;k=k+1)
   if(trained[k] && !(stage<2 && k<2) && k!=stage && distances[k]<min_cross)min_cross=distances[k];
  if(stage>=2 && trained[0] && trained[1] && envelope_distance<min_cross)min_cross=envelope_distance;
 end
 always @(posedge clk)begin
  decision_sample<=0;pose_valid<=0;
  if(rst || clear_models)begin
   state<=IDLE;bin<=0;source_counts<=0;source_area<=0;source_id<=0;
   source_edges<=0;last_edges<=0;wrist_edges<=0;cal_count<=0;cal_area_sum<=0;
   numerator<=0;quotient<=0;remainder<=0;step<=0;cal_distance<=0;cal_restart<=0;cal_finishing<=0;
   trained<=0;template_index<=0;distance_sum<=0;training_compare<=0;candidate_area<=0;
   envelope_sum<=0;envelope_distance<=8191;
   model_ready<=0;stage<=0;collecting<=0;error<=0;pose<=0;best_distance<=0;
   have_id<=0;last_id<=0;age<=0;decision_sample<=0;decision_id<=0;decision_label<=0;
   for(i=0;i<6;i=i+1)begin distances[i]<=8191;template_area[i]<=0;end
  end else begin
   if(age<STALE_CYCLES)age<=age+1'b1;
   if(capture)begin
    state<=IDLE;collecting<=1;cal_count<=0;cal_area_sum<=0;error<=0;pose<=0;
    if(model_ready)begin model_ready<=0;trained<=0;stage<=0;end
   end else if(!enabled)begin
    state<=IDLE;cal_count<=0;pose<=0;have_id<=0;last_id<=0;age<=0;
   end else if(fresh)begin
    have_id<=1;last_id<=frame_id;age<=0;
    if(!candidate_valid || bad_clip || area<24 || state!=IDLE)begin
     state<=IDLE;cal_count<=0;pose<=0;decision_sample<=1;decision_id<=frame_id;decision_label<=0;
     if(state!=IDLE)error<=3;
    end else if(collecting || model_ready)begin
     source_counts<=counts;source_area<=area;source_id<=frame_id;source_edges<=edges;bin<=0;state<=N_INIT;
    end
   end else if(age>=STALE_CYCLES-1)begin state<=IDLE;cal_count<=0;pose<=0;end
   else case(state)
    IDLE:;
    N_INIT:begin
     numerator<=({8'd0,source_counts[bin*9 +:9]}<<8)-source_counts[bin*9 +:9];
     quotient<=0;remainder<=0;step<=0;state<=N_STEP;
    end
    N_STEP:begin
     numerator<=numerator<<1;quotient<=next_q;
     remainder<=take ? trial-{1'b0,source_area} : trial;
     if(step==16)state<=N_STORE;else step<=step+1'b1;
    end
    N_STORE:begin
     if(bin==15)begin bin<=0;state<=collecting ? CAL_INIT : R_ADDR;template_index<=0;training_compare<=0;distance_sum<=0;envelope_sum<=0;end
     else begin bin<=bin+1'b1;state<=N_INIT;end
    end
    CAL_INIT:begin cal_distance<=0;bin<=0;state<=CAL_WAIT;end
    CAL_WAIT:state<=CAL_ACC;
    CAL_ACC:begin
     cal_distance<=cal_distance+cal_delta;
     if(bin==15)state<=CAL_DECIDE;else begin bin<=bin+1'b1;state<=CAL_WAIT;end
    end
    CAL_DECIDE:begin
     last_edges<=source_edges;
     cal_restart<=cal_count==0 || cal_distance>CAL_JITTER || (stage==0 && source_edges!=last_edges);
     cal_finishing<=cal_count==2 && cal_distance<=CAL_JITTER && !(stage==0 && source_edges!=last_edges);
     candidate_area<=(cal_area_sum+source_area+1)/3;
     bin<=0;state<=C_WRITE_WAIT;
    end
    C_WRITE_WAIT:state<=C_WRITE;
    C_WRITE:begin
     if(bin==15)begin
      bin<=0;
      if(cal_finishing)begin training_compare<=1;template_index<=0;distance_sum<=0;envelope_sum<=0;state<=R_ADDR;end
      else begin
       cal_count<=cal_restart ? 1 : 2;
       cal_area_sum<=cal_restart ? source_area : cal_area_sum+source_area;
       state<=IDLE;
      end
     end else begin bin<=bin+1'b1;state<=C_WRITE_WAIT;end
    end
    R_ADDR:state<=R_WAIT;
    R_WAIT:state<=R_ACC;
    R_ACC:begin
     distance_sum<=distance_sum+template_delta;
     if(template_index==0)begin
      envelope_sum<=envelope_sum+envelope_delta;
      if(bin==15)envelope_distance<=trained[0] && trained[1] ? envelope_sum+envelope_delta : 13'd8191;
     end
     if(bin==15)begin
      distances[template_index]<=trained[template_index] ? distance_sum+template_delta : 13'd8191;
      bin<=0;distance_sum<=0;
      if(template_index==5)state<=DECIDE;
      else begin template_index<=template_index+1'b1;state<=R_ADDR;end
     end else begin bin<=bin+1'b1;state<=R_ADDR;end
    end
    DECIDE:begin
     if(training_compare)begin
      if(min_cross<MIN_SEPARATION)begin error<=2;collecting<=0;cal_count<=0;state<=IDLE;end
      else begin bin<=0;state<=WRITE_WAIT;end
     end else begin
      best_distance<=ranked_best;decision_id<=source_id;decision_sample<=1;pose_valid<=1;
      if(ranked_best<=ACCEPT_DISTANCE && {1'b0,ranked_second}>={1'b0,ranked_best}+CLASS_MARGIN &&
         {1'b0,source_area}>=({1'b0,template_area[winning_template]}>>1) &&
         {1'b0,source_area}<={template_area[winning_template],1'b0})begin
       pose<=ranked_label;decision_label<=ranked_label;
      end else begin pose<=0;decision_label<=0;end
      state<=IDLE;
     end
    end
    WRITE_WAIT:state<=WRITE;
    WRITE:begin
     if(bin==15)begin
      trained[stage]<=1;template_area[stage]<=candidate_area;collecting<=0;cal_count<=0;error<=0;state<=IDLE;
      if(stage==0)wrist_edges<=source_edges;
      if(stage==5)begin model_ready<=1;stage<=6;end else stage<=stage+1'b1;
     end else begin bin<=bin+1'b1;state<=WRITE_WAIT;end
    end
    default:begin state<=IDLE;error<=3;end
   endcase
  end
 end
endmodule

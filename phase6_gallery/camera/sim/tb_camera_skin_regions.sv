`timescale 1ns/1ps
module tb_camera_skin_regions #(parameter MAX_AREA=1200,MAX_ASPECT=3,FEATURES=0);
    reg clk=0;always #5 clk=~clk;
    reg rst=1,begin_frame=0,end_frame=0,enabled=1,sample_valid=0;
    reg dense=0,motion_seed=0,foreground_seed=0;
    reg [6:0] x=0;reg [5:0] y=0;
    wire done,valid,overflow;wire [12:0] area,core,motion_count;wire [18:0] sum_x,sum_y;
    wire [6:0] min_x,max_x;wire [5:0] min_y,max_y;
    wire reference_valid=0;wire [9:0] reference_x=0,reference_y=0,reference_width=0,reference_height=0;
    wire [143:0] shape_counts;
    reg passed=0;
    camera_palm_regions #(.MIN_SEEDS(0),.MIN_FOREGROUND_SEEDS(3),.MAX_AREA(MAX_AREA),.MAX_ASPECT(MAX_ASPECT),.SHAPE_FEATURES(FEATURES)) dut(.*);
    task feature_check(input integer mode);
        integer expected[0:15];integer total,index;
        begin
            for(integer j=0;j<16;j=j+1)expected[j]=0;
            for(integer yy=0;yy<60;yy=yy+1)for(integer xx=0;xx<80;xx=xx+1)begin
                if((mode==0 && large_skin(xx,yy)) || (mode==4 && hand_skin(xx,yy)) ||
                   (mode==9 && xx>=10 && xx<70 && yy>=10 && yy<50))begin
                    index=(yy/15)*4+xx/20;expected[index]=expected[index]+1;
                end
            end
            total=0;
            for(integer j=0;j<16;j=j+1)begin
                if(shape_counts[j*9+:9]!=expected[j])$fatal(1,"Selected component feature %d mode=%d actual=%d expected=%d",j,mode,shape_counts[j*9+:9],expected[j]);
                total=total+shape_counts[j*9+:9];
            end
            if(total!=area)$fatal(1,"Feature counts do not sum to selected area");
        end
    endtask
    function large_skin(input integer xx,yy);
        large_skin=xx>=20 && xx<40 && yy>=15 && yy<35;
    endfunction
    function hand_skin(input integer xx,yy);
        hand_skin=xx>=50 && xx<56 && yy>=20 && yy<26;
    endfunction
    task run_case(input integer mode);
        integer waits;
        begin
            @(negedge clk);begin_frame=1;
            @(negedge clk);begin_frame=0;
            for(integer yy=0;yy<60;yy=yy+1)for(integer xx=0;xx<80;xx=xx+1)begin
                sample_valid=1;x=xx;y=yy;
                dense=mode==6 ? 1 : mode==7 ? xx%2==0 && yy%2==0 :
                    large_skin(xx,yy) || (mode==4 && hand_skin(xx,yy));
                if(mode==8)dense=xx>=20 && xx<60 && yy>=10 && yy<50;
                if(mode==9 || mode==10)dense=xx>=10 && xx<70 && yy>=10 && yy<(mode==9 ? 50 : 51);
                if(mode==11 || mode==12)dense=xx>=20 && xx<(mode==11 ? 31 : 28) && yy>=10 && yy<48;
                foreground_seed=0;motion_seed=0;
                case(mode)
                    0,5:foreground_seed=dense && (yy==15 || (yy==16 && xx<25)); // exactly 25/400
                    1:foreground_seed=dense && (yy==15 || (yy==16 && xx<24)); // 24/400 rejected
                    2:foreground_seed=dense && yy==15 && xx<22;             // fewer than 3
                    4:foreground_seed=hand_skin(xx,yy) && yy==20 && xx<53;   // supported small hand
                    6,7:foreground_seed=dense;
                    default:foreground_seed=0;
                endcase
                motion_seed=(mode==0 && xx==20 && yy==15) || (mode==4 && foreground_seed);
                if(mode>=8)begin foreground_seed=dense;motion_seed=dense;end
                @(negedge clk);sample_valid=0;
                repeat(7)@(negedge clk);
            end
            end_frame=1;@(negedge clk);end_frame=0;
            waits=0;while(!done && waits<34010)begin @(negedge clk);waits=waits+1;end
            if(!done)$fatal(1,"Skin region analysis missed budget mode=%d",mode);
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=0;
        run_case(0);
        if(FEATURES)feature_check(0);
        if(!valid || overflow || area!=400 || core!=324 || sum_x!=11800 || sum_y!=9800 ||
            min_x!=20 || max_x!=39 || min_y!=15 || max_y!=34 || motion_count!=1)
            $fatal(1,"Full skin geometry / separate support and motion failed A=%d C=%d motion=%d",area,core,motion_count);
        run_case(1);if(valid || overflow)$fatal(1,"Insufficient support ratio accepted");
        run_case(2);if(valid || overflow)$fatal(1,"Too few foreground seeds accepted");
        run_case(3);if(valid || overflow)$fatal(1,"Unsupported static skin accepted");
        run_case(4);
        if(FEATURES)feature_check(4);
        if(!valid || overflow || area!=36 || core!=16 || min_x!=50 || min_y!=20 || motion_count!=3)
            $fatal(1,"Larger unsupported skin distractor stole candidate A=%d",area);
        run_case(5);
        if(!valid || overflow || area!=400 || motion_count!=0)$fatal(1,"Supported static hold requires false motion");
        run_case(6);if(valid || !overflow)$fatal(1,"Full skin overload failed open");
        run_case(7);if(valid || !overflow)$fatal(1,"Skin component noise overload failed open");
        run_case(8);
        if(MAX_AREA>=1600)begin
            if(!valid || overflow || area!=1600 || core!=1444)$fatal(1,"Large 1600-cell region lost or exceeded budget");
        end else if(valid)$fatal(1,"Legacy area limit changed");
        run_case(9);
        if(FEATURES && MAX_AREA>=2400)feature_check(9);
        if(MAX_AREA>=2400)begin
            if(!valid || overflow || area!=2400 || core!=2204)$fatal(1,"Inclusive 2400-cell region lost or exceeded budget");
        end else if(valid)$fatal(1,"Legacy large region accepted");
        run_case(10);if(valid)$fatal(1,"2460-cell region exceeded area cap");
        run_case(11);
        if(MAX_ASPECT>=4)begin
            if(!valid || overflow || area!=418 || core!=324)$fatal(1,"Natural narrow side-palm region lost");
        end else if(valid)$fatal(1,"Legacy aspect ratio changed");
        run_case(12);if(valid)$fatal(1,"Region beyond 4:1 aspect accepted");
        passed=1;$display("PASS SKIN REGIONS: 80x60 full geometry, support ratio/count, static distractor, separate motion, hold and overload");$finish;
    end
    initial begin #10000000;$fatal(1,"Skin region test timeout");end
endmodule

`timescale 1ns/1ps
module tb_camera_identity_selection;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,begin_frame=0,end_frame=0,sample_valid=0,dense=0;
 reg [6:0] x=0;reg [5:0] y=0;
 wire done,valid,overflow;wire [12:0] area;wire [18:0] sum_x,sum_y;
 wire [6:0] min_x,max_x;wire [5:0] min_y,max_y;
 wire [40:0] selection_reference;
 wire old_done,old_valid;wire [12:0] old_area;
 reg sample_tick=0,restart=0;reg [31:0] frame_id=0;
 reg [9:0] cx=0,cy=0,width=0,height=0;
 wire [2:0] state,reason,direction,event_direction;wire armed,event_valid,target_visible;
 wire [31:0] event_sequence;
 reg passed=0;
 camera_palm_regions #(.MIN_SEEDS(0),.MAX_AREA(2400),.MAX_ASPECT(4),.STRICT_SELECT(1),.PREFER_TRACK(1)) dut(
  .clk(clk),.rst(rst),.begin_frame(begin_frame),.end_frame(end_frame),.enabled(1'b1),
  .sample_valid(sample_valid),.x(x),.y(y),.dense(dense),.motion_seed(dense),.foreground_seed(dense),
  .reference_valid(selection_reference[40]),.reference_x(selection_reference[39:30]),.reference_y(selection_reference[29:20]),
  .reference_width(selection_reference[19:10]),.reference_height(selection_reference[9:0]),
  .done(done),.valid(valid),.overflow(overflow),.area(area),.core(),.motion_count(),.sum_x(sum_x),.sum_y(sum_y),
  .min_x(min_x),.max_x(max_x),.min_y(min_y),.max_y(max_y),.shape_counts());
 camera_palm_regions #(.MIN_SEEDS(0),.MAX_AREA(2400),.MAX_ASPECT(4)) baseline(
  .clk(clk),.rst(rst),.begin_frame(begin_frame),.end_frame(end_frame),.enabled(1'b1),
  .sample_valid(sample_valid),.x(x),.y(y),.dense(dense),.motion_seed(dense),.foreground_seed(dense),
  .reference_valid(1'b0),.reference_x(10'd0),.reference_y(10'd0),.reference_width(10'd0),.reference_height(10'd0),
  .done(old_done),.valid(old_valid),.overflow(),.area(old_area),.core(),.motion_count(),.sum_x(),.sum_y(),
  .min_x(),.max_x(),.min_y(),.max_y(),.shape_counts());
 camera_swipe_tracker tracker(.clk(clk),.rst(rst),.enabled(1'b1),.restart(restart),.epoch_reset(1'b0),
  .sample_valid(sample_tick),.candidate_valid(valid),.clipped(1'b0),.edges(4'd0),.frame_id(frame_id),
  .cx(cx),.cy(cy),.width(width),.height(height),.state(state),.reason(reason),.direction(direction),
  .armed(armed),.event_valid(event_valid),.event_direction(event_direction),.event_sequence(event_sequence),
  .origin_x(),.origin_y(),.target_visible(target_visible));
 camera_selection_reference reference_control(.clk(clk),.reset(rst || restart),
  .identity_state(state==1 || state==2 || state==3),.sample_tick(sample_tick),.candidate_valid(valid),
  .cx(cx),.cy(cy),.width(width),.height(height),.selection_reference(selection_reference));
 task frame(input integer hx,hy,input integer face_present);
  integer waits;
  begin
   @(negedge clk);begin_frame=1;@(negedge clk);begin_frame=0;
   for(integer yy=0;yy<60;yy=yy+1)for(integer xx=0;xx<80;xx=xx+1)begin
    sample_valid=1;x=xx;y=yy;
    dense=(hx>=0 && xx>=hx && xx<hx+10 && yy>=hy && yy<hy+10) ||
          (face_present && xx>=55 && xx<75 && yy>=6 && yy<26) ||
          (face_present==2 && xx>=45 && xx<55 && yy==25);
    @(negedge clk);sample_valid=0;repeat(3)@(negedge clk);
   end
   end_frame=1;@(negedge clk);end_frame=0;
   waits=0;while(!done && waits<34010)begin @(negedge clk);waits=waits+1;end
   if(!done || !old_done || overflow)$fatal(1,"Identity frame failed budget");
   if(face_present==1 && (!old_valid || old_area!=400))$fatal(1,"Old baseline did not reproduce large-face selection");
   if(valid)begin
    cx=(sum_x/area)*8+4;cy=(sum_y/area)*8+4;
    width=(max_x-min_x+1)*8;height=(max_y-min_y+1)*8;
   end
   frame_id=frame_id+1;sample_tick=1;@(negedge clk);sample_tick=0;
   repeat(4)@(negedge clk);
  end
 endtask
 task rearm;
  begin
   restart=1;@(negedge clk);restart=0;
   repeat(5)frame(35,25,1);
   if(state!=2 || !selection_reference[40] || area!=100)$fatal(1,"Central hand did not arm against larger face");
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst=0;
  repeat(3)frame(-1,0,1);
  if(valid || armed || event_sequence!=0)$fatal(1,"Peripheral face acquired without central hand");
  for(integer dir=2;dir<=5;dir=dir+1)begin
   rearm;
   frame(dir==2 ? 32 : dir==3 ? 38 : 35,dir==4 ? 22 : dir==5 ? 28 : 25,1);
   frame(dir==2 ? 29 : dir==3 ? 41 : 35,dir==4 ? 19 : dir==5 ? 31 : 25,1);
   repeat(2)frame(dir==2 ? 29 : dir==3 ? 41 : 35,dir==4 ? 19 : dir==5 ? 31 : 25,1);
   if(event_sequence!=dir-1 || event_direction!=dir)$fatal(1,"Identity changed/lost four-way gesture dir=%d count=%d",dir,event_sequence);
  end
  rearm;frame(-1,0,1);
  if(valid || armed || selection_reference[40])$fatal(1,"Lost hand fell back to distant face");
  repeat(2)frame(-1,0,1);
  if(valid || event_sequence!=4)$fatal(1,"Face completed a missing hand trajectory");
  rearm;
  // A distant new hand cannot inherit the reference; reacquire centrally.
  frame(10,25,0);
  if(valid || armed)$fatal(1,"Distant component inherited tracked identity");
  rearm;
  frame(35,25,2);
  if(valid || armed || event_sequence!=4)$fatal(1,"Merged enlarged component inherited identity");
  rearm;
  restart=1;@(negedge clk);restart=0;
  frame(-1,0,1);
  if(valid || selection_reference[40])$fatal(1,"KEY3 retained identity");
  passed=1;$display("PASS IDENTITY SELECTION: old face wins vs central hand, all four events, no distant fallback, loss/reacquire and KEY3");$finish;
 end
 initial begin #60000000;$fatal(1,"Identity selection watchdog");end
endmodule

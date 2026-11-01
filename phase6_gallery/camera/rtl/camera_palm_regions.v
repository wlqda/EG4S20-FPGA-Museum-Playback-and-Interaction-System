// Packed-mask scanline flood fill between complete frames. Bounded stack and
// processing budget fail CLOSED. 4-connected components are scored separately.
module camera_palm_regions #(
    parameter integer GW=80,GH=60,MIN_AREA=24,MAX_AREA=1200,MIN_CORE=4,MIN_SEEDS=3,
    parameter integer STACK_SIZE=128,MAX_COMPONENTS=64,MAX_CYCLES=34000,
    parameter PREFER_TRACK=0,STRICT_SELECT=0,
    parameter integer MIN_FOREGROUND_SEEDS=0,MAX_ASPECT=3,SHAPE_FEATURES=0
)(input wire clk,rst,begin_frame,end_frame,enabled,sample_valid,
  input wire [6:0] x,input wire [5:0] y,input wire dense,motion_seed,foreground_seed,
  input wire reference_valid,
  input wire [9:0] reference_x,reference_y,reference_width,reference_height,
  output reg done,valid,overflow,output reg [12:0] area,core,motion_count,
  output reg [18:0] sum_x,sum_y,
  output reg [6:0] min_x,max_x,output reg [5:0] min_y,max_y,
  output reg [143:0] shape_counts);
    localparam PIXELS=GW*GH,WORDS=PIXELS/16,FW=PIXELS/4,SPW=$clog2(STACK_SIZE+1),WAW=$clog2(WORDS),
        SAW=STACK_SIZE>1 ? $clog2(STACK_SIZE) : 1;
    localparam IDLE=0,SCAN_READ=1,SCAN_WAIT=2,SCAN_CHECK=3,POP=4,POP_WAIT=5,POP_LOAD=6,
        READ=7,WAIT_RAM=8,CHECK_SEED=9,CHECK_LEFT=10,CHECK_RUN=11,CHECK_NEIGHBOR=12,EVALUATE=13;
    (* ram_style="bram_9k" *) reg [15:0] work_mask[0:WORDS-1];
    (* ram_style="bram_9k" *) reg [15:0] features[0:FW-1];
    (* ram_style="bram_9k" *) reg [12:0] stack[0:STACK_SIZE-1];
    reg [15:0] mask_pack,feature_pack,work_q,feature_q;
    reg [12:0] stack_q;
    reg [SPW-1:0] sp;
    reg [GW-1:0] row1,row2;
    reg [1:0] win0,win1,win2;
    // Complete raster samples arrive in x order, even when clocks between
    // samples are stalled. Shift lines avoid two variable 80-to-1 read muxes.
    wire is_core=x>=2 && y>=2 && dense && (&win0) && row1[0] && (&win1) && row2[0] && (&win2);
    wire [12:0] capture_address=y*GW+x;
    wire [15:0] next_mask={dense,mask_pack[15:1]};
    wire [15:0] next_feature={{foreground_seed,motion_seed,is_core,dense},feature_pack[15:4]};
    reg [3:0] state,check_state;
    reg [6:0] cx,run_left,run_right;
    reg [5:0] cy,run_y;
    reg below,prev_on;
    reg [6:0] scan_col;
    reg [5:0] scan_y;
    wire [12:0] cursor=cy*GW+cx;
    wire scan_mode=state==SCAN_READ || state==SCAN_WAIT || state==SCAN_CHECK;
    wire [12:0] read_word=scan_mode ? scan_y*(GW/16)+scan_col : cursor>>4;
    wire on_bit=work_q[cursor[3:0]];
    wire [3:0] feature_cell=feature_q >> {cursor[1:0],2'b00};
    reg [12:0] ca,cc,cs,cf;
    reg [143:0] shape_work;
    wire [1:0] shape_col=cx<GW/4 ? 0 : cx<GW/2 ? 1 : cx<GW*3/4 ? 2 : 3;
    wire [1:0] shape_row=cy<GH/4 ? 0 : cy<GH/2 ? 1 : cy<GH*3/4 ? 2 : 3;
    wire [3:0] shape_index={shape_row,shape_col};
    reg [18:0] sx,sy;
    reg [6:0] lx,hx;
    reg [5:0] ly,hy;
    reg [14:0] best_score;
    reg best_preferred,prefer_active;
    reg [9:0] ref_x,ref_y,ref_width,ref_height;
    wire [14:0] score={2'b0,ca}+({2'b0,cc}<<2);
    wire [7:0] bw={1'b0,hx}-{1'b0,lx}+1'b1;
    wire [6:0] bh={1'b0,hy}-{1'b0,ly}+1'b1;
    wire [14:0] rectangle=bw*bh;
    // Bbox midpoint is a cheap association prefilter; the tracker still checks
    // the selected region's actual centroid before accepting an update.
    wire [9:0] center_x=({3'b0,lx}+{3'b0,hx}+10'd1)<<2;
    wire [9:0] center_y=({4'b0,ly}+{4'b0,hy}+10'd1)<<2;
    wire [10:0] width_pixels={bw,3'b000};
    wire [9:0] height_pixels={bh,3'b000};
    wire [9:0] delta_x=center_x>=ref_x ? center_x-ref_x : ref_x-center_x;
    wire [9:0] delta_y=center_y>=ref_y ? center_y-ref_y : ref_y-center_y;
    wire [10:0] association_limit=({1'b0,ref_width}+{1'b0,ref_height})/4+24;
    wire preferred=prefer_active &&
        {1'b0,delta_x}<=(STRICT_SELECT ? association_limit : ({1'b0,ref_width}>>1)+11'd8) &&
        {1'b0,delta_y}<=(STRICT_SELECT ? association_limit : ({1'b0,ref_height}>>1)+11'd8) &&
        (width_pixels<<1)>={1'b0,ref_width} && width_pixels<={ref_width,1'b0} &&
        {height_pixels,1'b0}>={1'b0,ref_height} && {1'b0,height_pixels}<={ref_height,1'b0};
    // Central acquisition is applied before ranking components. Once acquired,
    // no distant fallback may replace a missing target in strict mode.
    wire central=center_x>=256 && center_x<=384 && center_y>=184 && center_y<=296;
    wire selection_allowed=!STRICT_SELECT || (prefer_active ? preferred : central);
    // Background support selects a whole skin component. It is independent of
    // temporal motion, which is still required by the tracker for acquisition.
    wire foreground_supported=MIN_FOREGROUND_SEEDS==0 ||
        (cf>=MIN_FOREGROUND_SEEDS && ({4'b0,cf}<<4)>={4'b0,ca});
    wire acceptable=foreground_supported && ca>=MIN_AREA && ca<=MAX_AREA && cc>=MIN_CORE && ({4'b0,cc}<<4)>={4'b0,ca} &&
        cs>=MIN_SEEDS && bw>=4 && bh>=4 && bw<=bh*MAX_ASPECT && bh<=bw*MAX_ASPECT && ca*3>=rectangle;
    reg [15:0] budget;
    reg [6:0] components;
    function [3:0] first_one;
        input [15:0] bits_in;
        integer k;reg found;
        begin first_one=0;found=0;for(k=0;k<16;k=k+1)if(!found && bits_in[k])begin first_one=k;found=1;end end
    endfunction
    wire [6:0] found_x=(scan_col<<4)+first_one(work_q);
    // One explicit write port avoids synthesis expanding the mutually
    // exclusive capture/clear writes into a register bank and large mux.
    wire [12:0] mask_write_word=sample_valid ? capture_address>>4 : cursor>>4;
    wire mask_write=sample_valid ? capture_address[3:0]==15 : state==CHECK_RUN && on_bit;
    wire [15:0] mask_write_data=sample_valid ? next_mask : work_q & ~(16'b1<<cursor[3:0]);
    wire stack_scan_write=state==SCAN_CHECK && work_q!=0 && components<MAX_COMPONENTS;
    wire stack_neighbor_write=state==CHECK_NEIGHBOR && on_bit && !prev_on && sp<STACK_SIZE;
    wire [SAW-1:0] stack_write_address=stack_scan_write ? 0 : sp[SAW-1:0];
    wire [SPW-1:0] stack_read_pointer=sp-1'b1;
    wire [SAW-1:0] stack_read_address=stack_read_pointer[SAW-1:0];
    wire [12:0] stack_write_data=stack_scan_write ? {scan_y,found_x} : {cy,cx};
    // Synchronous RAM reads; CHECK states follow a full wait cycle.
    always @(posedge clk)begin
        work_q<=work_mask[read_word[WAW-1:0]];feature_q<=features[cursor>>2];
        stack_q<=stack[stack_read_address];
        if(!rst && !begin_frame && mask_write && mask_write_word<WORDS)
            work_mask[mask_write_word[WAW-1:0]]<=mask_write_data;
        if(!rst && !begin_frame && sample_valid)begin
            if(capture_address[1:0]==3)features[capture_address>>2]<=next_feature;
        end
        // Normalize the mutually exclusive writes into ONE RAM port. Separate
        // statements expand this 128x13 stack into registers in TD synthesis.
        if(!rst && !begin_frame && (stack_scan_write || stack_neighbor_write))
            stack[stack_write_address]<=stack_write_data;
    end
    always @(posedge clk)begin
        done<=0;
        if(rst)begin
            state<=IDLE;check_state<=CHECK_SEED;done<=0;valid<=0;overflow<=0;
            area<=0;core<=0;motion_count<=0;sum_x<=0;sum_y<=0;min_x<=0;max_x<=0;min_y<=0;max_y<=0;
            mask_pack<=0;feature_pack<=0;row1<=0;row2<=0;win0<=0;win1<=0;win2<=0;
            cx<=0;cy<=0;run_left<=0;run_right<=0;run_y<=0;below<=0;prev_on<=0;
            scan_col<=0;scan_y<=0;sp<=0;ca<=0;cc<=0;cs<=0;cf<=0;sx<=0;sy<=0;
            lx<=127;hx<=0;ly<=63;hy<=0;best_score<=0;budget<=0;components<=0;
            best_preferred<=0;prefer_active<=0;ref_x<=0;ref_y<=0;ref_width<=0;ref_height<=0;
            shape_work<=0;shape_counts<=0;
        end else if(begin_frame)begin
            // A stale analysis must never overlap writes of the next frame.
            if(state!=IDLE)begin valid<=0;overflow<=1;done<=1;end
            state<=IDLE;mask_pack<=0;feature_pack<=0;row1<=0;row2<=0;win0<=0;win1<=0;win2<=0;
        end else begin
            if(sample_valid)begin
                mask_pack<=next_mask;feature_pack<=next_feature;
                row1<={dense,row1[GW-1:1]};row2<={row1[0],row2[GW-1:1]};
                if(x==0)begin win0<={1'b0,dense};win1<={1'b0,row1[0]};win2<={1'b0,row2[0]};end
                else begin win0<={win0[0],dense};win1<={win1[0],row1[0]};win2<={win2[0],row2[0]};end
            end
            if(end_frame)begin
                valid<=0;overflow<=0;area<=0;core<=0;motion_count<=0;best_score<=0;components<=0;budget<=0;
                shape_counts<=0;
                scan_col<=0;scan_y<=0;sp<=0;
                best_preferred<=0;prefer_active<=PREFER_TRACK && reference_valid;
                ref_x<=reference_x;ref_y<=reference_y;ref_width<=reference_width;ref_height<=reference_height;
                if(enabled)state<=SCAN_READ;
                else begin state<=IDLE;done<=1;end
            end else if(state!=IDLE && budget>=MAX_CYCLES-1)begin
                state<=IDLE;done<=1;valid<=0;overflow<=1;area<=0;core<=0;motion_count<=0;
            end else begin
                if(state!=IDLE)budget<=budget+1'b1;
                case(state)
                    IDLE:;
                    SCAN_READ:state<=SCAN_WAIT;
                    SCAN_WAIT:state<=SCAN_CHECK;
                    SCAN_CHECK:begin
                        if(work_q==0)begin
                            if(scan_col==GW/16-1)begin
                                scan_col<=0;
                                if(scan_y==GH-1)begin state<=IDLE;done<=1;end
                                else begin scan_y<=scan_y+1'b1;state<=SCAN_READ;end
                            end else begin scan_col<=scan_col+1'b1;state<=SCAN_READ;end
                        end else if(components>=MAX_COMPONENTS)begin state<=IDLE;done<=1;overflow<=1;valid<=0;area<=0;core<=0;motion_count<=0;end
                        else begin
                            components<=components+1'b1;sp<=1;ca<=0;cc<=0;cs<=0;cf<=0;sx<=0;sy<=0;
                            shape_work<=0;
                            lx<=127;hx<=0;ly<=63;hy<=0;state<=POP;
                        end
                    end
                    POP:if(sp==0)state<=EVALUATE;else state<=POP_WAIT;
                    POP_WAIT:state<=POP_LOAD;
                    POP_LOAD:begin cx<=stack_q[6:0];cy<=stack_q[12:7];sp<=sp-1'b1;check_state<=CHECK_SEED;state<=READ;end
                    READ:state<=WAIT_RAM;
                    WAIT_RAM:state<=check_state;
                    CHECK_SEED:begin
                        if(!on_bit)state<=POP;
                        else if(cx==0)begin run_left<=0;run_y<=cy;check_state<=CHECK_RUN;state<=READ;end
                        else begin cx<=cx-1'b1;check_state<=CHECK_LEFT;state<=READ;end
                    end
                    CHECK_LEFT:begin
                        if(on_bit && cx!=0)begin cx<=cx-1'b1;state<=READ;end
                        else begin
                            run_left<=on_bit ? cx : cx+1'b1;
                            if(!on_bit)cx<=cx+1'b1;
                            run_y<=cy;check_state<=CHECK_RUN;state<=READ;
                        end
                    end
                    CHECK_RUN:begin
                        if(on_bit)begin
                            ca<=ca+1'b1;sx<=sx+cx;sy<=sy+cy;
                            if(feature_cell[1])cc<=cc+1'b1;
                            if(feature_cell[2])cs<=cs+1'b1;
                            if(feature_cell[3])cf<=cf+1'b1;
                            // Independent constant slices avoid a wide dynamic
                            // read/modify/write mux on the histogram counter.
                            if(SHAPE_FEATURES)for(integer b=0;b<16;b=b+1)
                                if(shape_index==b)shape_work[b*9 +:9]<=shape_work[b*9 +:9]+1'b1;
                            if(cx<lx)lx<=cx;if(cx>hx)hx<=cx;if(cy<ly)ly<=cy;if(cy>hy)hy<=cy;
                        end
                        if(on_bit && cx<GW-1)begin cx<=cx+1'b1;state<=READ;end
                        else begin
                            run_right<=on_bit ? cx : cx-1'b1;cx<=run_left;prev_on<=0;
                            if(run_y!=0)begin cy<=run_y-1'b1;below<=0;end
                            else begin cy<=run_y+1'b1;below<=1;end
                            check_state<=CHECK_NEIGHBOR;state<=READ;
                        end
                    end
                    CHECK_NEIGHBOR:begin
                        if(on_bit && !prev_on && sp>=STACK_SIZE)begin state<=IDLE;done<=1;valid<=0;overflow<=1;area<=0;core<=0;motion_count<=0;end
                        else begin
                            if(on_bit && !prev_on)sp<=sp+1'b1;
                            prev_on<=on_bit;
                            if(cx<run_right)begin cx<=cx+1'b1;state<=READ;end
                            else if(!below && run_y<GH-1)begin cx<=run_left;cy<=run_y+1'b1;below<=1;prev_on<=0;state<=READ;end
                            else state<=POP;
                        end
                    end
                    EVALUATE:begin
                        if(acceptable && selection_allowed && ((!best_preferred && preferred) ||
                            (preferred==best_preferred && score>best_score)))begin
                            best_preferred<=preferred;
                            best_score<=score;valid<=1;area<=ca;core<=cc;motion_count<=cs;sum_x<=sx;sum_y<=sy;
                            min_x<=lx;max_x<=hx;min_y<=ly;max_y<=hy;
                            if(SHAPE_FEATURES)shape_counts<=shape_work;
                        end
                        state<=SCAN_READ;
                    end
                    default:begin state<=IDLE;done<=1;valid<=0;overflow<=1;end
                endcase
            end
        end
    end
endmodule

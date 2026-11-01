// Recognition telemetry for the gesture/pose pipeline: one fixed-format ASCII
// record per analysed frame, per delivered gesture event, per watched state
// change, and per heartbeat. 8N1, 115200, CRLF terminated, 73 bytes.
//
// Record (hex fields, fixed positions):
//   G1 F=<frame id 4> S=<stage 1> R=<reason 1> P=<pose 1> V=<event dir 1>
//      M=<armed,visible,valid,clipped 1> C=<cx 3>,<cy 3> W=<w 3>,<h 3>
//      A=<area 4> E=<edges 1> K=<bg_ready,fault,overflow,dvp_locked 1>
//      N=<event count 4>
// The line is 73 characters, so a log line always parses the same way:
//   G1 F=0A2C S=2 R=0 P=0 V=3 M=C C=140,0F0 W=060,090 A=1A2C E=0 K=9 N=0004
//
// Interpretation:
//   F  advances once per analysed source frame. A frozen F means the camera or
//      the analysis side stalled; it is never evidence that the hand stopped.
//   S  tracker state: 0 search, 1 confirm, 2 armed, 3 track, 4 return.
//   R  rejection/exit reason for the current state.
//   P  direction the tracker is currently proposing (0 = none).
//   V  direction of the last delivered event; N counts delivered events, so V
//      and N never change without a real event. That is what makes this log
//      usable as acceptance evidence instead of video review.
//   M  bit3 armed, bit2 target visible, bit1 candidate valid this frame,
//      bit0 candidate clipped by the ROI.
//   A  measured region area in 8x8 cells; C/W the measured centroid and extent.
//   E  {bottom,top,right,left} ROI edge-touch mask.
//   K  bit3 background ready, bit2 source fault, bit1 navigation queue
//      overflow, bit0 DVP polarity locked.
//
// Rate budget: one record is 730 bit times, so at 115200 the line sustains about
// 157 records/s. A 30 fps analysis fits with a wide margin; if the analysis ever
// ran faster, the busy flag drops surplus records instead of truncating or
// interleaving them.
//
// Implementation note: the record is generated one byte at a time from a latched
// snapshot of the raw fields (about 110 bits) instead of from a 584-bit ASCII
// concatenation. That keeps the whole feature at roughly 150 LUTs, which matters
// because this design is close to the LUT limit, and it still guarantees that a
// record cannot change halfway through: the snapshot is taken when the line
// starts, not when each byte is assembled.
module camera_telemetry_uart #(
    parameter integer CLK_HZ=25000000,
    parameter integer BAUD=115200,
    parameter integer HEARTBEAT_CYCLES=CLK_HZ/2
)(
    input wire clk,rst,
    input wire [31:0] frame_id,event_sequence,
    input wire [2:0] stage,reason,pose,event_direction,
    input wire armed,target_visible,candidate_valid,clipped,
    input wire background_ready,source_fault,nav_overflow,dvp_locked,
    input wire [9:0] cx,cy,width,height,
    input wire [12:0] area,input wire [3:0] edges,
    input wire sample_tick,event_valid,output reg tx
);
    localparam integer BYTES=73;
    localparam integer DIV=CLK_HZ/BAUD;
    localparam integer DIV_W=DIV>1 ? $clog2(DIV) : 1;
    localparam integer HW=HEARTBEAT_CYCLES>1 ? $clog2(HEARTBEAT_CYCLES) : 1;

    function [7:0] hexchar;
        input [3:0] v;
        begin hexchar=v<10 ? 8'h30+v : 8'h37+v;end
    endfunction

    // Snapshot of the raw fields, taken once per record.
    reg [15:0] f_q,n_q;
    reg [2:0] s_q,r_q,p_q,v_q;
    reg [3:0] m_q,e_q,k_q;
    reg [9:0] x_q,y_q,w_q,h_q;
    reg [12:0] a_q;

    // Last delivered event is latched here, not read live, so a record queued
    // behind a busy transmitter still reports the event that fired.
    reg [2:0] seen_direction;
    reg [15:0] seen_sequence;
    reg pending_event;
    // Slow-changing fields only. Per-frame fields (candidate valid, centroid,
    // area) are in the payload but must not trigger a record on their own.
    reg [10:0] watch_q;
    reg [HW-1:0] beat;
    wire [10:0] watch={stage,reason,armed,background_ready,source_fault,nav_overflow,dvp_locked};
    wire beat_tick=beat==HEARTBEAT_CYCLES-1;

    reg busy,byte_busy;
    reg [6:0] index;
    reg [DIV_W-1:0] baud_count;
    reg [3:0] bit_index;
    reg [9:0] shift;
    wire start=!busy && (pending_event || watch!=watch_q || beat_tick || sample_tick);

    // Character selection: a hex nibble for the numeric fields, a literal for
    // the punctuation and labels. Index 0 is 'G' and index 72 is LF.
    reg is_hex;
    reg [3:0] nibble;
    reg [7:0] literal;
    always @(*)begin
        is_hex=1'b1;nibble=4'h0;literal=8'h20;
        case(index)
            7'd0:begin is_hex=0;literal="G";end
            7'd1:begin is_hex=0;literal="1";end
            7'd3:begin is_hex=0;literal="F";end
            7'd4:begin is_hex=0;literal="=";end
            7'd5:nibble=f_q[15:12];
            7'd6:nibble=f_q[11:8];
            7'd7:nibble=f_q[7:4];
            7'd8:nibble=f_q[3:0];
            7'd10:begin is_hex=0;literal="S";end
            7'd11:begin is_hex=0;literal="=";end
            7'd12:nibble={1'b0,s_q};
            7'd14:begin is_hex=0;literal="R";end
            7'd15:begin is_hex=0;literal="=";end
            7'd16:nibble={1'b0,r_q};
            7'd18:begin is_hex=0;literal="P";end
            7'd19:begin is_hex=0;literal="=";end
            7'd20:nibble={1'b0,p_q};
            7'd22:begin is_hex=0;literal="V";end
            7'd23:begin is_hex=0;literal="=";end
            7'd24:nibble={1'b0,v_q};
            7'd26:begin is_hex=0;literal="M";end
            7'd27:begin is_hex=0;literal="=";end
            7'd28:nibble=m_q;
            7'd30:begin is_hex=0;literal="C";end
            7'd31:begin is_hex=0;literal="=";end
            7'd32:nibble={2'b00,x_q[9:8]};
            7'd33:nibble=x_q[7:4];
            7'd34:nibble=x_q[3:0];
            7'd35:begin is_hex=0;literal=",";end
            7'd36:nibble={2'b00,y_q[9:8]};
            7'd37:nibble=y_q[7:4];
            7'd38:nibble=y_q[3:0];
            7'd40:begin is_hex=0;literal="W";end
            7'd41:begin is_hex=0;literal="=";end
            7'd42:nibble={2'b00,w_q[9:8]};
            7'd43:nibble=w_q[7:4];
            7'd44:nibble=w_q[3:0];
            7'd45:begin is_hex=0;literal=",";end
            7'd46:nibble={2'b00,h_q[9:8]};
            7'd47:nibble=h_q[7:4];
            7'd48:nibble=h_q[3:0];
            7'd50:begin is_hex=0;literal="A";end
            7'd51:begin is_hex=0;literal="=";end
            7'd52:nibble={3'b000,a_q[12]};
            7'd53:nibble=a_q[11:8];
            7'd54:nibble=a_q[7:4];
            7'd55:nibble=a_q[3:0];
            7'd57:begin is_hex=0;literal="E";end
            7'd58:begin is_hex=0;literal="=";end
            7'd59:nibble=e_q;
            7'd61:begin is_hex=0;literal="K";end
            7'd62:begin is_hex=0;literal="=";end
            7'd63:nibble=k_q;
            7'd65:begin is_hex=0;literal="N";end
            7'd66:begin is_hex=0;literal="=";end
            7'd67:nibble=n_q[15:12];
            7'd68:nibble=n_q[11:8];
            7'd69:nibble=n_q[7:4];
            7'd70:nibble=n_q[3:0];
            7'd71:begin is_hex=0;literal=8'h0d;end
            7'd72:begin is_hex=0;literal=8'h0a;end
            default:begin is_hex=0;literal=8'h20;end
        endcase
    end
    wire [7:0] character=is_hex ? hexchar(nibble) : literal;

    always @(posedge clk)begin
        if(rst)begin
            f_q<=0;n_q<=0;s_q<=0;r_q<=0;p_q<=0;v_q<=0;m_q<=0;e_q<=0;k_q<=0;
            x_q<=0;y_q<=0;w_q<=0;h_q<=0;a_q<=0;
            seen_direction<=0;seen_sequence<=0;pending_event<=0;
            watch_q<=11'h7ff;beat<=0;
            busy<=0;byte_busy<=0;index<=0;baud_count<=0;bit_index<=0;shift<=0;tx<=1;
        end else begin
            beat<=beat_tick ? 0 : beat+1'b1;
            if(event_valid)begin
                seen_direction<=event_direction;seen_sequence<=event_sequence[15:0];pending_event<=1;
            end else if(start)pending_event<=0;
            if(start)begin
                // Latch one coherent snapshot before the first byte leaves.
                f_q<=frame_id[15:0];n_q<=seen_sequence;
                s_q<=stage;r_q<=reason;p_q<=pose;v_q<=seen_direction;
                m_q<={armed,target_visible,candidate_valid,clipped};
                x_q<=cx;y_q<=cy;w_q<=width;h_q<=height;a_q<=area;
                e_q<=edges;k_q<={background_ready,source_fault,nav_overflow,dvp_locked};
                watch_q<=watch;
                busy<=1;byte_busy<=0;index<=0;
            end else if(!busy)tx<=1;
            if(busy && !byte_busy)begin
                // Frame is {stop,data[7:0],start}; bit_index counts the ten wire
                // bits so the stop bit is a real full bit time, not a gap.
                shift<={1'b1,character,1'b0};bit_index<=0;baud_count<=DIV-1;
                byte_busy<=1;tx<=0;
            end else if(busy && byte_busy)begin
                if(baud_count!=0)baud_count<=baud_count-1'b1;
                else begin
                    baud_count<=DIV-1;
                    if(bit_index==9)begin
                        byte_busy<=0;tx<=1;
                        if(index==BYTES-1)busy<=0;
                        else index<=index+1'b1;
                    end else begin
                        shift<={1'b1,shift[9:1]};tx<=shift[1];bit_index<=bit_index+1'b1;
                    end
                end
            end
        end
    end
endmodule

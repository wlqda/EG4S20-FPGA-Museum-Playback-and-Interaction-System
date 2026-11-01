`timescale 1ns/1ps
// Verifies the recognition telemetry line: exact 73-byte framing, CRLF, fixed
// field positions, hex encoding, per-frame trigger with busy drop, heartbeat,
// state-change trigger, event latch and no splice when live inputs change while
// a record is still in flight.
module tb_camera_telemetry;
    reg clk=0;always #5 clk=~clk;
    reg rst=1;
    reg [31:0] frame_id=0,event_sequence=0;
    reg [2:0] stage=0,reason=0,pose=0,event_direction=0;
    reg armed=0,target_visible=0,candidate_valid=0,clipped=0;
    reg background_ready=0,source_fault=0,nav_overflow=0,dvp_locked=0;
    reg [9:0] cx=0,cy=0,width=0,height=0;
    reg [12:0] area=0;reg [3:0] edges=0;
    reg sample_tick=0,event_valid=0;
    wire tx;
    reg passed=0;
    integer received=0;
    localparam integer BYTES=73;
    // CLK_HZ/BAUD = 10 clocks per bit, so one record is ~7300 clocks. The
    // heartbeat is 100000 clocks, far longer than the whole scripted sequence, so
    // every scripted record below is triggered by a frame tick, a state change or
    // an event; case 8 is the only one that waits for the heartbeat itself.
    camera_telemetry_uart #(.CLK_HZ(1000),.BAUD(100),.HEARTBEAT_CYCLES(100000)) dut(.*);

    task receive_byte(output reg [7:0] value);
        begin
            @(negedge tx);
            repeat(5)@(posedge clk);#1;
            if(tx!==0)$fatal(1,"telemetry: missing start bit");
            for(integer i=0;i<8;i=i+1)begin repeat(10)@(posedge clk);#1;value[i]=tx;end
            repeat(10)@(posedge clk);#1;
            if(tx!==1)$fatal(1,"telemetry: missing stop bit");
        end
    endtask

    // Compare one captured record against the expected 73-byte string, echoing
    // it in readable form because that is what the operator will actually see.
    // The receiver must already be armed before the record starts, so every
    // caller forks the trigger into `fire`.
    task expect_line(input [BYTES*8-1:0] expected);
        reg [7:0] value;
        begin
            for(integer i=0;i<BYTES;i=i+1)begin
                receive_byte(value);
                if(value!==expected[BYTES*8-1-i*8 -: 8])
                    $fatal(1,"telemetry byte %0d: expected %h (%s) got %h (%s)",i,
                        expected[BYTES*8-1-i*8 -: 8],expected[BYTES*8-1-i*8 -: 8],value,value);
                if(value!=8'h0d && value!=8'h0a)$write("%c",value);
            end
            $write("\n");
            received=received+1;
        end
    endtask

    function [7:0] hx(input [3:0] d);
        begin hx=d<10 ? 8'h30+d : 8'h37+d;end
    endfunction

    // Builds the expected record from the same field widths the RTL uses, so a
    // layout change on either side shows up as a byte mismatch.
    function [BYTES*8-1:0] record(input [15:0] f,input [3:0] s,input [3:0] r,input [3:0] p,
        input [3:0] v,input [3:0] m,input [9:0] x,input [9:0] y,input [9:0] w,input [9:0] h,
        input [12:0] a,input [3:0] e,input [3:0] k,input [15:0] n);
        begin
            record={"G1 F=",hx(f[15:12]),hx(f[11:8]),hx(f[7:4]),hx(f[3:0]),
                " S=",hx(s)," R=",hx(r)," P=",hx(p)," V=",hx(v)," M=",hx(m),
                " C=",hx({2'b0,x[9:8]}),hx(x[7:4]),hx(x[3:0]),",",
                     hx({2'b0,y[9:8]}),hx(y[7:4]),hx(y[3:0]),
                " W=",hx({2'b0,w[9:8]}),hx(w[7:4]),hx(w[3:0]),",",
                     hx({2'b0,h[9:8]}),hx(h[7:4]),hx(h[3:0]),
                " A=",hx({3'b0,a[12:12]}),hx(a[11:8]),hx(a[7:4]),hx(a[3:0]),
                " E=",hx(e)," K=",hx(k),
                " N=",hx(n[15:12]),hx(n[11:8]),hx(n[7:4]),hx(n[3:0]),8'h0d,8'h0a};
        end
    endfunction

    // Waits for an idle line first, so a trigger is never silently swallowed by
    // the tail of the previous record. Case 6 deliberately drops frames and so
    // uses raw_frame instead.
    task fire_frame;
        begin
            wait(!dut.busy);
            @(negedge clk);sample_tick=1;
            @(negedge clk);sample_tick=0;
        end
    endtask

    task raw_frame;
        begin
            @(negedge clk);sample_tick=1;
            @(negedge clk);sample_tick=0;
        end
    endtask

    initial begin
        repeat(5)@(negedge clk);
        if(tx!==1)$fatal(1,"telemetry: TX must idle high in reset");
        rst=0;
        // Every field gets a distinctive non-trivial value.
        frame_id=32'h1234abcd;
        stage=2;reason=3;pose=2;
        armed=1;target_visible=1;candidate_valid=1;clipped=0;
        background_ready=1;source_fault=0;nav_overflow=0;dvp_locked=1;
        cx=10'h141;cy=10'h0f3;width=10'h051;height=10'h07e;
        area=13'h1a2c;edges=4'h5;

        // 1. A frame tick emits exactly one record; low 16 bits of the frame id
        //    and both M/K nibbles must round-trip.
        fork
            expect_line(record(16'habcd,4'h2,4'h3,4'h2,4'h0,4'he,10'h141,10'h0f3,10'h051,10'h07e,
                13'h1a2c,4'h5,4'h9,16'h0000));
            fire_frame;
        join

        // 2. One record per analysed frame, so the next frame updates the trace.
        frame_id=32'habce;cx=10'h150;
        fork
            expect_line(record(16'habce,4'h2,4'h3,4'h2,4'h0,4'he,10'h150,10'h0f3,10'h051,10'h07e,
                13'h1a2c,4'h5,4'h9,16'h0000));
            fire_frame;
        join

        // 3. A non-frame field changing must not emit on its own; only the next
        //    frame tick carries it. Nothing may appear in the meantime.
        candidate_valid=0;cx=10'h160;
        repeat(9000)@(negedge clk);
        if(received!=2)$fatal(1,"telemetry: a silent payload change emitted a record");

        // 4. A watched state change emits immediately, without a frame tick.
        stage=3;
        fork
            expect_line(record(16'habce,4'h3,4'h3,4'h2,4'h0,4'hc,10'h160,10'h0f3,10'h051,10'h07e,
                13'h1a2c,4'h5,4'h9,16'h0000));
            begin repeat(1)@(negedge clk); end
        join

        // 5. An event latches direction and count even though the stage is set.
        event_sequence=32'hdeadbeef;event_direction=3;frame_id=32'habcf;
        fork
            expect_line(record(16'habcf,4'h3,4'h3,4'h2,4'h3,4'hc,10'h160,10'h0f3,10'h051,10'h07e,
                13'h1a2c,4'h5,4'h9,16'hbeef));
            begin
                repeat(1)@(negedge clk);event_valid=1;sample_tick=1;
                @(negedge clk);event_valid=0;sample_tick=0;
            end
        join

        // 6. Frame ticks offered while the line is busy are dropped, never
        //    truncated, and the following record reflects the newest snapshot
        //    instead of a mixture of the two.
        frame_id=32'habd0;cx=10'h170;
        fork
            fork
                expect_line(record(16'habd0,4'h3,4'h3,4'h2,4'h3,4'hc,10'h170,10'h0f3,10'h051,10'h07e,
                    13'h1a2c,4'h5,4'h9,16'hbeef));
                fire_frame;
            join
            begin
                repeat(200)@(negedge clk);
                // Scramble payload fields while that record is in flight, and keep
                // ticking frames so the transmitter is offered records it must
                // drop. Only per-frame fields change here, so nothing extra may
                // be emitted and the next record shows the newest snapshot.
                frame_id=32'h0000ffff;cx=10'h3ff;cy=10'h3ff;area=13'h1fff;edges=4'hf;
                repeat(6)raw_frame;
                frame_id=32'habd1;cx=10'h180;cy=10'h0f1;area=13'h0abc;edges=4'h2;
            end
        join

        // 7. The final snapshot appears intact on the next record (the state
        //    changed, so this is immediate rather than heartbeat-driven).
        stage=4;
        fork
            expect_line(record(16'habd1,4'h4,4'h3,4'h2,4'h3,4'hc,10'h180,10'h0f1,10'h051,10'h07e,
                13'h0abc,4'h2,4'h9,16'hbeef));
            begin repeat(1)@(negedge clk); end
        join

        // 8. With no frames and no changes, the heartbeat still proves the link
        //    is alive and repeats the last state. No trigger here: the receiver
        //    just waits for the line to start on its own.
        expect_line(record(16'habd1,4'h4,4'h3,4'h2,4'h3,4'hc,10'h180,10'h0f1,10'h051,10'h07e,
            13'h0abc,4'h2,4'h9,16'hbeef));

        // 9. Reset must park the line idle high and clear the latched event.
        @(negedge clk);rst=1;
        repeat(5)@(negedge clk);
        if(tx!==1)$fatal(1,"telemetry: reset must release TX high");
        rst=0;
        stage=0;reason=0;pose=0;
        frame_id=32'h00000001;event_sequence=0;cx=10'h0aa;cy=10'h0bb;
        width=10'h010;height=10'h020;area=13'h0010;edges=4'h0;
        armed=0;target_visible=0;candidate_valid=1;clipped=1;
        background_ready=1;source_fault=0;nav_overflow=0;dvp_locked=1;
        fork
            expect_line(record(16'h0001,4'h0,4'h0,4'h0,4'h0,4'h3,10'h0aa,10'h0bb,10'h010,10'h020,
                13'h0010,4'h0,4'h9,16'h0000));
            fire_frame;
        join

        // Case 3 fires no frame tick on purpose, so it produces no record: eight
        // captured records is the expected total for the whole sequence.
        if(received!=8)$fatal(1,"telemetry: expected 8 records, got %0d",received);
        passed=1;
        $display("PASS TELEMETRY: 73-byte fixed layout, CRLF, hex fields, per-frame trigger, busy drop, heartbeat, change trigger, event latch, no splice, reset");
        $finish;
    end

    initial begin #5000000;$fatal(1,"telemetry test timed out");end
endmodule

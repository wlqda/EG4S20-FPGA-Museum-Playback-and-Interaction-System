// TD-compatible Verilog translation; see corresponding .sv and LICENSE.
/*
 * Copyright lizhirui
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Change Logs:
 * Date           Author       Notes
 * 2022-08-27     lizhirui     the first version
 */

module museum_phase1_sd_reader #(
        parameter[4:0] CLK_DIV = 5'd2,
        parameter SIMULATION = 0,
        parameter RX_PIPE_DELAY = 2
    )(
        input wire rstn,
        input wire clk,

        output wire sdclk,
        input wire sdcmdin,
        output wire sdcmdout,
        output wire sdcmdoe,
        input wire[3:0] sddat,

        output wire[1:0] card_type,
        output wire[3:0] card_stat,

        input wire rstart,
        input wire[31:0] rsector,
        input wire[22:0] rsector_num,
        output wire rsuspend,
        input wire rresume,
        output reg rresume_ack,
        output wire rbusy,
        output wire rdone,

        output reg integrity_error,
        output reg block_valid,
        output reg [3:0] integrity_lanes,
        output reg high_speed_ok,
        output reg switch_error,
        output reg outen,
        output reg[31:0] outaddr,
        output reg[7:0] outbyte
    );

    localparam UNKNOWN=0, SDv1=1, SDv2=2, SDHCv2=3, SDv1Maybe=4;
    // card_type_t represented as reg [2:0]

    localparam CMD0=0, CMD8=1, CMD55_41=2, ACMD41=3, CMD2=4, CMD3=5, CMD7=6, CMD55_6=7, ACMD6=8, CMD6=9, CMD16=10, CMD18=11, CMD18_WAITING_RESPONSE=12, DATA_READING=13, DATA_CMD12=14, DATA_WAITING_STOP=15;
    // card_state_t represented as reg [3:0]

    localparam WAITING_BLOCK=0, READING_BLOCK_DATA=1, READING_BLOCK_TAIL=2, READY_TO_SUSPEND=3, SUSPEND=4, READ_FINISH=5, READ_STOP=6, READ_TIMEOUT=7;
    // sddat_state_t represented as reg [2:0]

    localparam reg[15:0] HIGHCLKDIV = 16'd1 << (CLK_DIV - 1);
    localparam reg[15:0] FASTCLKDIV = 16'd1 << CLK_DIV;
    localparam reg[15:0] SLOWCLKDIV = HIGHCLKDIV * (SIMULATION ? 16'd4 : 16'd125);

    wire sdclken;
    reg rx_clock,rx_clock_delayed,rx_clock_previous;
    always @(posedge clk)begin
        if(!rstn)begin rx_clock<=0;rx_clock_delayed<=0;rx_clock_previous<=0;end
        else begin
            rx_clock<=sdclk;rx_clock_delayed<=rx_clock;
            rx_clock_previous<=RX_PIPE_DELAY>=2 ? rx_clock_delayed : rx_clock;
        end
    end
    // Local changes: verify CMD6 selection and all four data CRC16 lanes.
    reg switch_response, switch_started, switch_complete;
    reg [7:0] switch_nibble;
    reg switch_selected;
    reg [15:0] data_crc[0:3];
    integer ci;
    function automatic [15:0] crc16_bit;
        input [15:0] c;input b;
        crc16_bit={c[14:0],1'b0} ^ ((c[15]^b) ? 16'h1021 : 16'h0000);
    endfunction
    (* mark_debug = "true" *)reg start;
    reg[15:0] precnt;
    reg[5:0] cmd;
    reg[31:0] arg;
    reg[15:0] clkdiv;
    reg[31:0] rsectoraddr;
    (* mark_debug = "true" *)wire busy;
    (* mark_debug = "true" *)wire done;
    (* mark_debug = "true" *)wire timeout;
    (* mark_debug = "true" *)wire syntaxe;
    wire[31:0] resparg;
    (* mark_debug = "true" *)reg[15:0] rca;
    (* mark_debug = "true" *)reg sdclkl;
    wire receive_tick=(RX_PIPE_DELAY!=0 && high_speed_ok) ?
        ((RX_PIPE_DELAY>=2 ? rx_clock_delayed : rx_clock) && !rx_clock_previous) : (sdclk && !sdclkl);

    reg[31:0] ridx;
    (* mark_debug = "true" *)reg[22:0] cur_relative_sector;
    (* mark_debug = "true" *)reg[22:0] sector_num;

    (* mark_debug = "true" *)reg [2:0] _card_type;

    (* mark_debug = "true" *)reg [3:0] cur_card_state, next_card_state;
    (* mark_debug = "true" *)reg [2:0] cur_sddat_state, next_sddat_state;

    always @(posedge clk) begin
        if(!rstn) begin
            switch_response<=0;switch_started<=0;switch_complete<=0;
            switch_nibble<=0;switch_selected<=0;high_speed_ok<=0;
            switch_error<=0;integrity_error<=0;integrity_lanes<=0;block_valid<=0;
            for(ci=0;ci<4;ci=ci+1) data_crc[ci]<=0;
        end else begin
            block_valid<=0;
            if(cur_card_state==CMD6 && busy && done && !timeout && !syntaxe)
                switch_response<=1;
            if(cur_card_state==CMD6 && !sdclkl && sdclk) begin
                if(!switch_started && sddat==0) begin
                    switch_started<=1;switch_nibble<=0;
                end else if(switch_started && !switch_complete) begin
                    if(switch_nibble==33) switch_selected<=sddat==1;
                    if(switch_nibble==144) begin
                        switch_complete<=1;high_speed_ok<=switch_selected;
                        switch_error<=!switch_selected;
                    end else switch_nibble<=switch_nibble+1'b1;
                end
            end
            if(receive_tick) begin
                if(cur_sddat_state==WAITING_BLOCK) begin
                    for(ci=0;ci<4;ci=ci+1) data_crc[ci]<=0;
                end else if(cur_sddat_state==READING_BLOCK_DATA ||
                        (cur_sddat_state==READING_BLOCK_TAIL && ridx<16)) begin
                    for(ci=0;ci<4;ci=ci+1) data_crc[ci]<=crc16_bit(data_crc[ci],sddat[ci]);
                end else if(cur_sddat_state==READING_BLOCK_TAIL && ridx==16) begin
                    if(!integrity_error && sddat==4'hf &&
                        data_crc[0]==0 && data_crc[1]==0 && data_crc[2]==0 && data_crc[3]==0)
                        block_valid<=1;
                    if(!integrity_error) begin
                        for(ci=0;ci<4;ci=ci+1) begin
                            integrity_lanes[ci]<=data_crc[ci]!=0 || !sddat[ci];
                            if(data_crc[ci]!=0 || !sddat[ci]) integrity_error<=1;
                        end
                    end
                end
            end
        end
    end

    assign rbusy = cur_card_state != CMD18;
    assign rdone = (cur_card_state == DATA_WAITING_STOP) && (cur_sddat_state == READ_STOP);

    assign card_type = _card_type[1:0];
    assign card_stat = cur_card_state[3:0];

    museum_phase1_sdcmd sdcmd_ctrl_inst(
        .rstn(rstn),
        .clk(clk),
        .sdclken(sdclken),
        .sdclk(sdclk),
        .sdcmdin(sdcmdin),
        .sdcmdout(sdcmdout),
        .sdcmdoe(sdcmdoe),
        .clkdiv(clkdiv),
        .start(start),
        .precnt(precnt),
        .cmd(cmd),
        .arg(arg),
        .busy(busy),
        .done(done),
        .timeout(timeout),
        .syntaxe(syntaxe),
        .resparg(resparg)
    );

    task automatic set_cmd;
        input _start;input [15:0] _precnt;input [5:0] _cmd;input [31:0] _arg;

        begin
        start = _start;
        precnt = _precnt;
        cmd = _cmd;
        arg = _arg;
        end
    endtask

    always @(posedge clk) begin
        if(!rstn) begin
            sdclkl <= 'b0;
        end
        else begin
            sdclkl <= sdclk;
        end
    end

    always @(posedge clk) begin
        if(!rstn) begin
            cur_card_state <= CMD0;
        end
        else begin
            cur_card_state <= next_card_state;
        end
    end

    always @* begin
        next_card_state = cur_card_state;

        if(cur_card_state==CMD6) begin
            if(switch_response && switch_complete && high_speed_ok)
                next_card_state=CMD16;
        end else if(((busy && done && (cur_card_state != CMD18))) || ((~busy) && (cur_card_state == CMD18)) || (cur_card_state == DATA_READING) || (cur_card_state == DATA_WAITING_STOP)) begin
            case(cur_card_state)
                CMD0: begin
                    next_card_state = CMD8;
                end

                CMD8: begin
                    if(timeout) begin
                        next_card_state = CMD55_41;
                    end
                    else if((~syntaxe) && (resparg[7:0] == 8'haa)) begin
                        next_card_state = CMD55_41;
                    end
                end

                CMD55_41: begin
                    if((~timeout) && (~syntaxe)) begin
                        next_card_state = ACMD41;
                    end
                end

                ACMD41: begin
                    if((~timeout) && (~syntaxe) && (resparg[31])) begin
                        next_card_state = CMD2;
                    end
                    else begin
                        next_card_state = CMD55_41;
                    end
                end

                CMD2: begin
                    if((~timeout) && (~syntaxe)) begin
                        next_card_state = CMD3;
                    end
                end

                CMD3: begin
                    if((~timeout) && (~syntaxe)) begin
                        next_card_state = CMD7;
                    end
                end

                CMD7: begin
                    if((~timeout) && (~syntaxe)) begin
                        next_card_state = CMD55_6;
                    end
                end

                CMD55_6: begin
                    if((~timeout) && (~syntaxe)) begin
                        next_card_state = ACMD6;
                    end
                end

                ACMD6: begin
                    if((~timeout) && (~syntaxe)) begin
                        next_card_state = CMD6;
                    end
                    else begin
                        next_card_state = CMD55_6;
                    end
                end

                CMD6: begin
                    if((~timeout) && (~syntaxe)) begin
                        next_card_state = CMD16;
                    end
                end

                CMD16: begin
                    if((~timeout) && (~syntaxe)) begin
                        next_card_state = CMD18;
                    end
                end

                CMD18: begin
                    if(rstart) begin
                        next_card_state = CMD18_WAITING_RESPONSE;
                    end
                end

                CMD18_WAITING_RESPONSE: begin
                    if((~timeout) && (~syntaxe)) begin
                        next_card_state = DATA_READING;
                    end
                end

                DATA_READING: begin
                    if(cur_sddat_state == READ_TIMEOUT) begin
                        next_card_state = CMD18_WAITING_RESPONSE;
                    end
                    else if(cur_sddat_state == READ_FINISH) begin
                        next_card_state = DATA_CMD12;
                    end
                end

                DATA_CMD12: begin
                    if((~timeout) && (~syntaxe)) begin
                        next_card_state = DATA_WAITING_STOP;
                    end
                end

                DATA_WAITING_STOP: begin
                    if(cur_sddat_state == READ_STOP) begin
                        next_card_state = CMD18;
                    end
                end
            endcase
        end
    end

    always @* begin
        set_cmd(0,16'd0,6'd0,32'd0);

        if((~busy) || (cur_card_state == DATA_READING)) begin
            case(cur_card_state)
                CMD0: begin
                    set_cmd(1, (SIMULATION ? 128 : 64000), 0, 'h00000000);
                end

                CMD8: begin
                    set_cmd(1, 24, 8, 'h000001aa);
                end

                CMD55_41: begin
                    set_cmd(1, 24, 55, 'h00000000);
                end

                ACMD41: begin
                    set_cmd(1, 24, 41, 'hc0100000);
                end

                CMD2: begin
                    set_cmd(1, 24, 2, 'h00000000);
                end

                CMD3: begin
                    set_cmd(1, 24, 3, 'h00000000);
                end

                CMD7: begin
                    set_cmd(1, 24, 7, {rca, 16'h0});
                end

                CMD55_6: begin
                    set_cmd(1, (SIMULATION ? 128 : 64000), 55, {rca, 16'h0});
                end

                ACMD6: begin
                    set_cmd(1, 24, 6, 'h00000002);
                end

                CMD6: begin
                    if(!switch_response) set_cmd(1, 24, 6, 'h8000fff1);
                end

                CMD16: begin
                    set_cmd(1, 200, 16, 'h00000200);
                end

                CMD18: begin
                    if(rstart) begin
                        set_cmd(1, 32, 18, rsector);
                    end
                end

                CMD18_WAITING_RESPONSE: begin
                    if(timeout || syntaxe || (~busy)) begin
                        set_cmd(1, 32, 18, rsectoraddr + cur_relative_sector);
                    end
                end

                DATA_CMD12: begin
                    set_cmd(1, 24, 12, 'h00000000);
                end
            endcase
        end
    end

    always @(posedge clk) begin
        if(!rstn) begin
            rca <= 'b0;
        end
        else if((cur_card_state == CMD3) && (next_card_state == CMD7)) begin
            rca <= resparg[31:16];
        end
    end

    always @(posedge clk) begin
        if(!rstn) begin
            _card_type <= UNKNOWN;
        end
        else if((cur_card_state == CMD8) && timeout) begin
            _card_type <= SDv1Maybe;
        end
        else if((cur_card_state == ACMD41) && (next_card_state == CMD2)) begin
            _card_type <= (_card_type == SDv1Maybe) ? SDv1 : (resparg[30] ? SDHCv2 : SDv2);
        end
    end

    always @(posedge clk) begin
        if(!rstn) begin
            clkdiv <= SLOWCLKDIV;
        end
        else if((cur_card_state == CMD7) && (next_card_state == CMD55_6)) begin
            clkdiv <= FASTCLKDIV;
        end
        else if((cur_card_state == CMD6) && (next_card_state == CMD16)) begin
            clkdiv <= HIGHCLKDIV;
        end
    end

    always @(posedge clk) begin
        if(!rstn) begin
            rsectoraddr <= 'b0;
            sector_num <= 'b0;
        end
        else if((~busy) && (cur_card_state == CMD18) && rstart) begin
            rsectoraddr <= rsector;
            sector_num <= rsector_num;
        end
    end

    always @(posedge clk) begin
        if(!rstn) begin
            cur_relative_sector <= 'b0;
        end
        else if((~busy) && (cur_card_state == CMD18) && rstart) begin
            cur_relative_sector <= 'b0;
        end
        else if(receive_tick && (cur_sddat_state == READING_BLOCK_TAIL) && (next_sddat_state == READY_TO_SUSPEND)) begin
            cur_relative_sector <= cur_relative_sector + 'b1;
        end
    end

    always @(posedge clk) begin
        if(!rstn) begin
            cur_sddat_state <= WAITING_BLOCK;
        end
        else if((cur_card_state != CMD18_WAITING_RESPONSE) && (next_card_state == CMD18_WAITING_RESPONSE)) begin
            cur_sddat_state <= WAITING_BLOCK;
        end
        else if((cur_card_state != CMD18_WAITING_RESPONSE) &&
                (cur_card_state != DATA_READING) && (cur_card_state != DATA_CMD12) &&
                (cur_card_state != DATA_WAITING_STOP)) begin
            cur_sddat_state <= WAITING_BLOCK;
        end
        else if(cur_sddat_state == SUSPEND) begin
            cur_sddat_state <= next_sddat_state;
        end
        else if(receive_tick) begin
            cur_sddat_state <= next_sddat_state;
        end
    end

    always @* begin
        next_sddat_state = cur_sddat_state;

        case(cur_sddat_state)
            WAITING_BLOCK: begin
                if(!sddat[0]) begin
                    next_sddat_state = READING_BLOCK_DATA;
                end
                else if(ridx > 5000000) begin// according to SD datasheet, 1ms is enough to wait for DAT result, here, we set timeout to 5000000 clock cycles = 100ms (when SDCLK=50MHz)
                    next_sddat_state = READ_TIMEOUT;
                end
            end

            READING_BLOCK_DATA: begin
                if((|ridx[31:10]) || (&ridx[9:0])) begin
                    next_sddat_state = READING_BLOCK_TAIL;
                end
            end

            READING_BLOCK_TAIL: begin
                if(|ridx[31:4]) begin//crc16 and a stop bit
                    next_sddat_state = READY_TO_SUSPEND;
                end
            end

            READY_TO_SUSPEND: begin
                if(|ridx[31:2]) begin//wait for 5 cycle for safely stopping clock
                    next_sddat_state = SUSPEND;
                end
            end

            SUSPEND: begin//this is 6th cycle
                if(cur_relative_sector == sector_num) begin
                    next_sddat_state = READ_FINISH;
                end
                else if(rresume) begin
                    next_sddat_state = WAITING_BLOCK;
                end
            end

            READ_FINISH: begin
                if(cur_card_state == DATA_WAITING_STOP) begin
                    // Exact >=63 comparison without a 32-bit carry chain.
                    if((|ridx[31:6]) || (&ridx[5:0])) begin
                        next_sddat_state = READ_STOP;
                    end
                end
            end

            READ_STOP: begin
                next_sddat_state = WAITING_BLOCK;
            end

            READ_TIMEOUT: begin
                //wait cmd resend
            end
        endcase
    end

    assign rsuspend = (cur_sddat_state == SUSPEND);
    assign sdclken = (cur_sddat_state != SUSPEND);

    always @(posedge clk) begin
        if(!rstn) begin
            rresume_ack <= 'b0;
        end
        else if((cur_sddat_state == SUSPEND) && rresume && (next_sddat_state != SUSPEND)) begin
            rresume_ack <= 'b1;
        end
        else begin
            rresume_ack <= 'b0;
        end
    end

    always @(posedge clk) begin
        if(!rstn) begin
            ridx <= 'b0;
        end
        else if((cur_card_state != CMD18_WAITING_RESPONSE) &&
                (cur_card_state != DATA_READING) && (cur_card_state != DATA_CMD12) &&
                (cur_card_state != DATA_WAITING_STOP)) begin
            ridx <= 'b0;
        end
        else if(receive_tick) begin
            if(cur_sddat_state != next_sddat_state) begin
                ridx <= 'b0;
            end
            else begin
                ridx <= ridx + 'b1;
            end
        end
    end

    always @(posedge clk) begin
        if(!rstn) begin
            outen <= 'b0;
            outaddr <= 'b0;
            outbyte <= 'b0;
        end
        else begin
            outen <= 'b0;
            outaddr <='b0;

            if(receive_tick && (cur_sddat_state == READING_BLOCK_DATA)) begin
                if(ridx[0] == 'b0) begin
                    outbyte[7:4] <= sddat;
                end
                else begin
                    outen <= 'b1;
                    outaddr <= {cur_relative_sector, ridx[9:1]};
                    outbyte[3:0] <= sddat;
                end
            end
        end
    end
endmodule

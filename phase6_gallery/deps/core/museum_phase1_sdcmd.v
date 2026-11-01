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

module museum_phase1_sdcmd(
        input wire rstn,
        input wire clk,

        input wire sdclken,
        output reg sdclk,

        input wire sdcmdin,
        output reg sdcmdout,
        output reg sdcmdoe,

        input wire[15:0] clkdiv,
        input wire start,
        input wire[15:0] precnt,
        input wire[5:0] cmd,
        input wire[31:0] arg,

        output reg busy,
        output reg done,
        output reg timeout,
        output reg syntaxe,
        output wire[31:0] resparg
    );

    function automatic [6:0] crc7;
        input [6:0] crc;input inbit;

        crc7={crc[5:0], crc[6] ^ inbit} ^ {3'b0, crc[6] ^ inbit, 3'b0};
    endfunction

    reg[5:0] req_cmd;
    reg[31:0] req_arg;
    reg[6:0] req_crc;reg [39:0] crc_payload;
    wire[51:0] request;

    reg[17:0] clkdivr;
    reg[17:0] clkcnt;
    reg[15:0] cnt1;
    reg[5:0] cnt2;
    reg[1:0] cnt3;
    reg[31:0] cnt4;
    reg[7:0] cnt5;

    reg sdclk_to_0;
    reg sdclk_to_1;

    reg [38:0] response;

    assign request = {6'b111101, req_cmd, req_arg, req_crc, 1'b1};
    assign resparg = response[31:0];

    always @(posedge clk) begin
        if(!rstn) begin
            clkdivr <= 'b0;
        end
        else if(clkcnt == 'b0) begin
            clkdivr <= {3'h0, clkdiv[15:1]};
        end
    end

    always @(posedge clk) begin
        if(!rstn) begin
            clkcnt <= 'b0;
        end
        else if((!sdclken) && (clkcnt == 'b0)) begin
            clkcnt <= 'b0;
        end
        else if(clkcnt < ({clkdivr[16:0], 1'b0} - 'b1)) begin
            clkcnt <= clkcnt + 'b1;
        end
        else begin
            clkcnt <= 'b0;
        end
    end

    always @* begin
        if(!rstn) begin
            sdclk_to_0 = 'b0;
            sdclk_to_1 = 'b0;
        end
        else if(sdclken || (clkcnt != 'b0)) begin
            if(clkcnt == 'b0) begin
                sdclk_to_0 = 'b1;
                sdclk_to_1 = 'b0;
            end
            else if(clkcnt == clkdivr[16:0]) begin
                sdclk_to_0 = 'b0;
                sdclk_to_1 = 'b1;
            end
            else begin
                sdclk_to_0 = 'b0;
                sdclk_to_1 = 'b0;
            end
        end
        else begin
            sdclk_to_0 = 'b0;
            sdclk_to_1 = 'b0;
        end
    end

    always @(posedge clk) begin
        if(!rstn) begin
            sdclk <= 'b0;
        end
        else if(sdclken || (clkcnt != 'b0)) begin
            if(sdclk_to_0) begin
                sdclk <= 'b0;
            end
            else if(sdclk_to_1) begin
                sdclk <= 'b1;
            end
        end
        else begin
            sdclk <= 'b0;
        end
    end

    always @(posedge clk) begin
        if(~rstn) begin
            {busy, done, timeout, syntaxe} <= 'b0;
            {sdcmdoe, sdcmdout} <= 2'b01;
            crc_payload<=0;{req_cmd, req_arg, req_crc} <= 'b0;
            response <= 'b0;
            cnt1 <= 'b0;
            cnt2 <= 6'h3f;
            cnt3 <= 'b0;
            cnt4 <= 'b0;
            cnt5 <= 8'hff;
        end
        else begin
            {done, timeout, syntaxe} <= 'b0;

            if(busy && done) begin
                busy <= 'b0;
            end
            else if((~busy) && start) begin
                busy <= 'b1;
                crc_payload<={2'b01,cmd,arg};req_cmd <= cmd;
                req_arg <= arg;
                req_crc <= 'b0;
                cnt1 <= precnt;
                cnt2 <= 6'd51;
                cnt3 <= 2'd2;
                cnt4 <= 'd250;
                cnt5 <= 8'd134;
            end
            else begin
                if(sdclk_to_0) begin
                    {sdcmdoe, sdcmdout} <= 2'b01;

                    if(cnt1 != 'b0) begin
                        cnt1 <= cnt1 - 'b1;
                    end
                    else if(cnt2 != 6'h3f) begin
                        cnt2 <= cnt2 - 'b1;
                        {sdcmdoe, sdcmdout} <= {1'b1, request[cnt2]};

                        if((cnt2 >= 8) && (cnt2 < 48)) begin
                            req_crc <= crc7(req_crc, crc_payload[39]);crc_payload<={crc_payload[38:0],1'b0};
                        end
                    end
                end
                else if(sdclk_to_1) begin
                    if((cnt1 == 'b0) && (cnt2 == 6'h3f)) begin
                        if(cnt3 != 'b0) begin
                            cnt3 <= cnt3 - 'b1;
                        end
                        else if(cnt4 != 'b0) begin
                            cnt4 <= cnt4 - 'b1;

                            if(~sdcmdin) begin//found start bit
                                cnt4 <= 'b0;
                            end
                            else if(cnt4 == 'b1) begin//timeout
                                done <= 'b1;
                                timeout <= 'b1;
                                syntaxe <= 'b0;
                            end
                        end
                        else if(cnt5 != 8'hff) begin
                            cnt5 <= cnt5 - 'b1;

                            if(cnt5 >= 'd96) begin
                                response <= {response[37:0], sdcmdin};
                            end
                            else if(cnt5 == 'b0) begin
                                done <= 'b1;
                                timeout <= 'b0;
                                syntaxe <= response[38] || ((response[37:32] != req_cmd) && (response[37:32] != 6'h3f) && (response[37:32] != 'b0));
                            end
                        end
                    end
                end
            end
        end
    end

endmodule

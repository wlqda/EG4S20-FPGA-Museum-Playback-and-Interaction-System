// OV5640 SCCB: 7-bit slave address, 16-bit register address, 8-bit data.
// Reads use STOP between the register-pointer write and read transaction.
// Both pins are open drain. External pull-ups are required.
module camera_sccb_master #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BUS_HZ = 100000,
    parameter integer TIMEOUT_CYCLES = 500000,
    parameter [6:0] DEVICE_ADDR = 7'h3c
)(
    input wire clk, rst, start, read_not_write,
    input wire [15:0] register_addr,
    input wire [7:0] write_data,
    inout wire scl, sda,
    output reg busy, done,
    output reg [7:0] read_data,
    // 0=success, 1=NACK, 2=transaction timeout, 3=SDA busy before START
    output reg [2:0] error,
    output reg [2:0] error_byte
);
    localparam integer QUARTER = CLK_HZ / (4 * BUS_HZ);
    localparam integer DIV_W = QUARTER > 1 ? $clog2(QUARTER) : 1;
    localparam integer WATCH_W = TIMEOUT_CYCLES > 1 ? $clog2(TIMEOUT_CYCLES) : 1;
    localparam IDLE=0, START_WAIT=1, START_HOLD=2, TX=3, ACK=4,
               RX=5, NACK=6, STOP_LOW=7, STOP_HIGH=8, STOP_RELEASE=9;
    reg [3:0] state;
    reg [DIV_W-1:0] divider;
    reg [WATCH_W-1:0] watchdog;
    reg scl_low, sda_low;
    (* async_reg="true" *) reg [1:0] scl_sync, sda_sync;
    reg [1:0] phase;
    reg [2:0] bit_index, byte_index;
    reg [7:0] tx_byte, rx_byte, data_q;
    reg [15:0] addr_q;
    reg read_q, reading, restart_after_stop;
    assign scl = scl_low ? 1'b0 : 1'bz;
    assign sda = sda_low ? 1'b0 : 1'bz;
    wire tick = divider == QUARTER-1;
    always @(posedge clk) begin
        if (rst) begin
            scl_sync <= 2'b11; sda_sync <= 2'b11;
        end else begin
            scl_sync <= {scl_sync[0], scl};
            sda_sync <= {sda_sync[0], sda};
        end
    end
    always @(posedge clk) begin
        done <= 0;
        if (rst) begin
            state<=IDLE; divider<=0; watchdog<=0;
            scl_low<=0; sda_low<=0; busy<=0; done<=0;
            error<=0; error_byte<=0; read_data<=0;
            phase<=0; bit_index<=7; byte_index<=0;
            tx_byte<=0; rx_byte<=0; addr_q<=0; data_q<=0;
            read_q<=0; reading<=0; restart_after_stop<=0;
        end else begin
            if (!busy || tick) divider<=0; else divider<=divider+1'b1;
            if (!busy) watchdog<=0; else watchdog<=watchdog+1'b1;
            if (busy && watchdog==TIMEOUT_CYCLES-1) begin
                state<=IDLE; busy<=0; done<=1; error<=2;
                error_byte<=byte_index; scl_low<=0; sda_low<=0;
            end else if (state==IDLE) begin
                if (start) begin
                    busy<=1; error<=0; error_byte<=0; read_data<=0;
                    addr_q<=register_addr; data_q<=write_data;
                    read_q<=read_not_write; reading<=0; restart_after_stop<=0;
                    byte_index<=0; tx_byte<={DEVICE_ADDR,1'b0}; bit_index<=7;
                    scl_low<=0; sda_low<=0; state<=START_WAIT;
                end
            end else if (tick) begin
                case (state)
                    START_WAIT: if (scl_sync[1]) begin
                        if (!sda_sync[1]) begin
                            error<=3; busy<=0; done<=1; state<=IDLE;
                        end else begin sda_low<=1; state<=START_HOLD; end
                    end
                    START_HOLD: begin scl_low<=1; phase<=0; state<=TX; end
                    TX: case (phase)
                        0: begin sda_low<=!tx_byte[bit_index]; phase<=1; end
                        1: begin scl_low<=0; phase<=2; end
                        2: if (scl_sync[1]) phase<=3;
                        3: begin
                            scl_low<=1; phase<=0;
                            if (bit_index==0) state<=ACK;
                            else bit_index<=bit_index-1'b1;
                        end
                    endcase
                    ACK: case (phase)
                        0: begin sda_low<=0; phase<=1; end
                        1: begin scl_low<=0; phase<=2; end
                        2: if (scl_sync[1]) begin
                            if (sda_sync[1]) begin error<=1; error_byte<=byte_index; end
                            phase<=3;
                        end
                        3: begin
                            scl_low<=1; phase<=0; bit_index<=7;
                            if (error!=0) begin restart_after_stop<=0; state<=STOP_LOW; end
                            else if (reading) begin rx_byte<=0; state<=RX; end
                            else case (byte_index)
                                0: begin byte_index<=1; tx_byte<=addr_q[15:8]; state<=TX; end
                                1: begin byte_index<=2; tx_byte<=addr_q[7:0]; state<=TX; end
                                2: if (read_q) begin restart_after_stop<=1; state<=STOP_LOW; end
                                   else begin byte_index<=3; tx_byte<=data_q; state<=TX; end
                                default: begin restart_after_stop<=0; state<=STOP_LOW; end
                            endcase
                        end
                    endcase
                    RX: case (phase)
                        0: begin sda_low<=0; phase<=1; end
                        1: begin scl_low<=0; phase<=2; end
                        2: if (scl_sync[1]) begin rx_byte[bit_index]<=sda_sync[1]; phase<=3; end
                        3: begin
                            scl_low<=1; phase<=0;
                            if (bit_index==0) begin read_data<=rx_byte; state<=NACK; end
                            else bit_index<=bit_index-1'b1;
                        end
                    endcase
                    NACK: case (phase)
                        0: begin sda_low<=0; phase<=1; end
                        1: begin scl_low<=0; phase<=2; end
                        2: if (scl_sync[1]) phase<=3;
                        3: begin scl_low<=1; restart_after_stop<=0; state<=STOP_LOW; phase<=0; end
                    endcase
                    STOP_LOW: begin sda_low<=1; scl_low<=1; state<=STOP_HIGH; end
                    STOP_HIGH: begin
                        scl_low<=0;
                        if (!scl_low && scl_sync[1]) state<=STOP_RELEASE;
                    end
                    STOP_RELEASE: begin
                        sda_low<=0;
                        if (restart_after_stop) begin
                            restart_after_stop<=0; reading<=1; byte_index<=4;
                            tx_byte<={DEVICE_ADDR,1'b1}; bit_index<=7; state<=START_WAIT;
                        end else begin state<=IDLE; busy<=0; done<=1; end
                    end
                    default: begin state<=IDLE; busy<=0; done<=1; error<=2; scl_low<=0; sda_low<=0; end
                endcase
            end
        end
    end
endmodule

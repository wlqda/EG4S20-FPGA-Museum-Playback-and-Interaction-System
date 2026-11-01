// museum_phase2_sd_sector: single-sector buffer over the integration group's SD block
// service (INTERFACES_V1 section 5). One 512-byte sector is collected, held until
// its CRC commit is seen, and only then offered to the client. Bytes from a sector
// that never commits are discarded, so no unverified data reaches the parsers.
//
// Client handshake:
//   req_valid/req_lba -> req_ready (accept) -> sector_valid (buffer readable,
//   stays high) -> read buf_data at buf_addr -> release (done) -> req_ready again.
//   sector_error rises instead of sector_valid when the sector did not commit.
module museum_phase2_sd_sector (
    input  wire        clk,
    input  wire        rst,
    input  wire        req_valid,
    input  wire [31:0] req_lba,
    output wire        req_ready,
    output reg         sector_valid,
    output reg         sector_error,
    input  wire        buf_release,
    input  wire [8:0]  buf_addr,
    output reg [7:0]  buf_data,
    output reg         rd_req_valid,
    output reg  [31:0] rd_lba,
    output reg  [22:0] rd_count,
    input  wire        rd_req_ready,
    input  wire [7:0]  rd_data,
    input  wire        rd_valid,
    input  wire        rd_sector_commit,
    input  wire        rd_done,
    input  wire [7:0]  rd_error,
    output reg         rd_resume
);
    localparam [2:0] ST_IDLE = 3'd0, ST_REQ = 3'd1, ST_DATA = 3'd2,
                     ST_FINISH = 3'd3, ST_HOLD = 3'd4;

    reg [2:0]  state;
    reg [9:0]  byte_cnt;
    reg        commit_seen, err_seen;
    reg        grace;
    (* ram_style="bram_9k" *) reg [7:0] sector_buf [0:511];

    always @(posedge clk)buf_data<=sector_buf[buf_addr];
    assign req_ready = (state == ST_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE; rd_req_valid <= 1'b0; rd_lba <= 32'd0; rd_count <= 23'd1;
            rd_resume <= 1'b0; sector_valid <= 1'b0; sector_error <= 1'b0;
            byte_cnt <= 10'd0; commit_seen <= 1'b0; err_seen <= 1'b0; grace <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    sector_valid <= 1'b0;
                    sector_error <= 1'b0;
                    if (req_valid) begin
                        rd_lba       <= req_lba;
                        rd_count     <= 23'd1;
                        rd_req_valid <= 1'b1;
                        byte_cnt     <= 10'd0;
                        commit_seen  <= 1'b0;
                        err_seen     <= 1'b0;
                        state        <= ST_REQ;
                    end
                end

                ST_REQ: if (rd_req_ready) begin
                    rd_req_valid <= 1'b0;
                    rd_resume    <= 1'b1;
                    state        <= ST_DATA;
                end

                ST_DATA: begin
                    if (rd_valid) begin
                        sector_buf[byte_cnt[8:0]] <= rd_data;
                        byte_cnt           <= byte_cnt + 10'd1;
                    end
                    if (rd_sector_commit) commit_seen <= 1'b1;
                    if (rd_error != 8'd0) err_seen     <= 1'b1;
                    if (rd_done) begin
                        rd_resume <= 1'b0;
                        grace     <= 1'b0;
                        state     <= ST_FINISH;
                    end
                end

                // One extra cycle of grace so a commit pulse arriving with or just
                // after rd_done is still observed.
                ST_FINISH: begin
                    if (rd_sector_commit) commit_seen <= 1'b1;
                    if (rd_error != 8'd0) err_seen     <= 1'b1;
                    if (grace) begin
                        if (err_seen || !(commit_seen || rd_sector_commit) ||
                            byte_cnt != 10'd512) begin
                            sector_error <= 1'b1;
                            sector_valid <= 1'b0;
                        end else begin
                            sector_valid <= 1'b1;
                            sector_error <= 1'b0;
                        end
                        state <= ST_HOLD;
                    end else begin
                        grace <= 1'b1;
                    end
                end

                ST_HOLD: if (buf_release) begin
                    sector_valid <= 1'b0;
                    state        <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule

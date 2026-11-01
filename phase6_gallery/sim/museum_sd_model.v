// museum_sd_model: behavioural model of the integration group's SD block service
// (INTERFACES_V1 section 5) for simulation. The testbench supplies boot, FAT and
// directory sectors through the mbr/bpb/fat/d0/d1 arrays, and BMP file sectors
// through the fmap table: fmap[lba - 2048] holds the byte offset of that LBA inside
// the file image, or 32'hFFFFFFFF for an LBA that is not part of a file.
//
// A sector whose LBA equals corrupt_lba streams its bytes but never asserts
// rd_sector_commit and raises rd_error, mirroring a CRC failure on real hardware.
module museum_sd_model (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] part_lba,
    input  wire [31:0] fat_lba,
    input  wire [31:0] fat_sectors,
    input  wire [31:0] root_lba,
    input  wire [31:0] corrupt_lba,
    input  wire [31:0] bmp_size,
    input  wire [15:0] bmp_w,
    input  wire [15:0] bmp_h,
    input  wire        bmp_bottom,
    input  wire [7:0]  bmp_seed,
    output reg  [7:0]  rd_data,
    output reg         rd_valid,
    output reg         rd_sector_commit,
    output reg         rd_done,
    output reg  [7:0]  rd_error,
    output reg         rd_req_ready,
    input  wire        rd_req_valid,
    input  wire [31:0] rd_lba,
    input  wire [22:0] rd_count,
    input  wire        rd_resume
);
    reg [7:0]  mbr [0:511];
    reg [7:0]  bpb [0:511];
    reg [7:0]  fat [0:8191];
    reg [7:0]  d0  [0:511];
    reg [7:0]  d1  [0:511];
    reg [7:0]  d2  [0:511];
    reg [31:0] fmap [0:8191];      // (lba - 2048) -> file byte offset, or all-ones

    localparam [2:0] M_IDLE = 3'd0, M_WAIT = 3'd1, M_SEND = 3'd2,
                     M_COMMIT = 3'd3, M_DONE = 3'd4;
    reg [2:0]  mst;
    reg [31:0] clba;
    reg [22:0] ccount, csec;
    reg [9:0]  cbyte;
    reg        cerr;

    // Pixel colour model, mirrored by the testbench checker.
    function [7:0] gen;
        input integer x, r, ch;
        begin gen = (x + r * 2 + ch * 7 + bmp_seed) & 8'hff; end
    endfunction

    // Byte `off` of the generated 24-bit BMP, laid out exactly like a real file.
    function [7:0] bmp_byte;
        input integer off;
        integer stride, p, r, c, x, ch, fsz;
        begin
            stride = ((bmp_w * 3 + 3) / 4) * 4;
            fsz    = 54 + stride * bmp_h;
            if (off < 54) begin
                case (off)
                    0:  bmp_byte = 8'h42;                       // "BM"
                    1:  bmp_byte = 8'h4d;
                    2:  bmp_byte = fsz[7:0];
                    3:  bmp_byte = fsz[15:8];
                    4:  bmp_byte = fsz[23:16];
                    5:  bmp_byte = fsz[31:24];
                    10: bmp_byte = 8'h36;                       // pixel offset 54
                    11: bmp_byte = 8'h00;
                    12: bmp_byte = 8'h00;
                    13: bmp_byte = 8'h00;
                    14: bmp_byte = 8'h28;                       // DIB size 40
                    15: bmp_byte = 8'h00;
                    16: bmp_byte = 8'h00;
                    17: bmp_byte = 8'h00;
                    18: bmp_byte = bmp_w[7:0];
                    19: bmp_byte = bmp_w[15:8];
                    22: bmp_byte = bmp_bottom ? bmp_h[7:0] : ((~bmp_h + 16'd1) & 16'h00ff);
                    23: bmp_byte = bmp_bottom ? bmp_h[15:8]
                                              : (((~bmp_h + 16'd1) >> 8) & 16'h00ff);
                    24: bmp_byte = bmp_bottom ? 8'h00 : 8'hff;
                    25: bmp_byte = bmp_bottom ? 8'h00 : 8'hff;
                    26: bmp_byte = 8'h01;                       // planes 1
                    28: bmp_byte = 8'h18;                       // 24 bpp
                    34: bmp_byte = (stride * bmp_h) & 8'hff;
                    default: bmp_byte = 8'h00;
                endcase
            end else begin
                p = off - 54;
                if (p >= stride * bmp_h) begin
                    bmp_byte = 8'h00;
                end else begin
                    r = p / stride;
                    c = p % stride;
                    if (c >= bmp_w * 3) begin
                        bmp_byte = 8'h00;
                    end else begin
                        x  = c / 3;
                        ch = c % 3;
                        bmp_byte = gen(x, r, ch);
                    end
                end
            end
        end
    endfunction

    function [7:0] db;
        input [31:0] lba;
        input integer off;
        integer idx, fo;
        begin
            if (lba == part_lba)          db = bpb[off];
            else if (lba >= fat_lba && lba < fat_lba + fat_sectors)
                                          db = fat[(lba - fat_lba) * 512 + off];
            else if (lba == root_lba)     db = d0[off];
            else if (lba == root_lba + 32'd1) db = d1[off];
            else if (lba == root_lba + 32'd2) db = d2[off];
            else if (lba == 32'd0)        db = mbr[off];
            else if (bmp_size != 32'd0 && lba >= 32'd2048 && lba < 32'd10240) begin
                idx = lba - 32'd2048;
                if (fmap[idx] == 32'hffffffff) db = 8'h00;
                else begin
                    fo = fmap[idx] + off;
                    if (fo < bmp_size) db = bmp_byte(fo);
                    else               db = 8'h00;
                end
            end else db = 8'h00;
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            mst <= M_IDLE; rd_req_ready <= 1'b1; rd_valid <= 1'b0;
            rd_sector_commit <= 1'b0; rd_done <= 1'b0; rd_error <= 8'h00;
            clba <= 0; ccount <= 0; csec <= 0; cbyte <= 0; cerr <= 1'b0;
        end else begin
            case (mst)
                M_IDLE: begin
                    rd_req_ready <= 1'b1;
                    rd_done      <= 1'b0;
                    rd_error     <= 8'h00;
                    rd_valid     <= 1'b0;
                    cbyte        <= 10'd0;
                    csec         <= 23'd0;
                    cerr         <= 1'b0;
                    if (rd_req_valid) begin
                        clba         <= rd_lba;
                        ccount       <= rd_count;
                        rd_req_ready <= 1'b0;
                        mst          <= M_WAIT;
                    end
                end

                M_WAIT: if (rd_resume) begin
                    cbyte <= 10'd0;
                    mst   <= M_SEND;
                end

                M_SEND: begin
                    rd_valid <= 1'b1;
                    rd_data  <= db(clba + {9'd0, csec}, cbyte);
                    if (cbyte == 10'd511) begin
                        cbyte <= 10'd0;
                        if ((clba + {9'd0, csec}) == corrupt_lba) cerr <= 1'b1;
                        else                                      rd_sector_commit <= 1'b1;
                        mst <= M_COMMIT;
                    end else begin
                        cbyte <= cbyte + 10'd1;
                    end
                end

                M_COMMIT: begin
                    rd_valid         <= 1'b0;
                    rd_sector_commit <= 1'b0;
                    if (csec + 23'd1 == ccount) begin
                        rd_error <= cerr ? 8'h05 : 8'h00;
                        rd_done  <= 1'b1;
                        mst      <= M_DONE;
                    end else begin
                        csec <= csec + 23'd1;
                        mst  <= M_WAIT;
                    end
                end

                M_DONE: begin
                    rd_done <= 1'b0;
                    mst     <= M_IDLE;
                end

                default: mst <= M_IDLE;
            endcase
        end
    end

    integer k;
    initial begin
        for (k = 0; k < 512; k = k + 1) begin
            mbr[k] = 8'h00; bpb[k] = 8'h00;
            d0[k]  = 8'h00; d1[k]  = 8'h00;
        end
        for (k = 0; k < 8192; k = k + 1) begin fat[k] = 8'h00; fmap[k] = 32'hffffffff; end
    end
endmodule

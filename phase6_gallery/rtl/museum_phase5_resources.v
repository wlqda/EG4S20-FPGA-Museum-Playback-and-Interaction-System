// museum_phase6_resources: index the BMP files on the TF card and stream a selected one
// out as an RGB888 image. Implements INTERFACES_V1 sections 4, 5 and 6.
//
// It owns the single SD block-service port and arbitrates it between the FAT32
// indexer (while scanning) and the file loader (while loading). The BMP parser runs
// as a child module and its pixel stream is passed straight through to the SDRAM
// image path owned by the integration group.
//
// Load sequence: image_begin (carrying the geometry the BMP header reported) is sent
// before any pixel, then the pixel stream, then image_end once the parser has
// finished and every file read committed. Any fault raises image_abort instead and
// no image_end is sent, so a failed file can never be presented as a good image.
module museum_phase6_resources #(
    parameter integer MAX_ENTRIES  = 29,
    parameter integer CANVAS_WIDTH = 640,
    parameter CACHE_AUDIO = 0
) (
    input wire [1:0] audio_raddr,
    output wire [3:0] audio_present,
    output wire [31:0] audio_cluster,audio_size,
    output wire [31:0] audio_fat_lba,audio_data_lba,audio_max_cluster,
    output wire [7:0] audio_spc,audio_scan_error,
    output wire [2:0] audio_shift,
    input  wire        mem_clk,
    input  wire        mem_rst,
    input  wire        scan_start,
    input  wire        select_valid,
    input  wire [15:0] select_index,
    output wire        select_ready,
    output wire [15:0] resource_count,
    output wire        scan_done,
    output wire        busy,
    output wire [7:0]  error,
    output wire        rd_req_valid,
    output wire [31:0] rd_lba,
    output wire [22:0] rd_count,
    input  wire        rd_req_ready,
    input  wire [7:0]  rd_data,
    input  wire        rd_valid,
    input  wire        rd_sector_commit,
    input  wire        rd_done,
    input  wire [7:0]  rd_error,
    output wire        rd_resume,
    output wire        image_begin_valid,
    input  wire        image_begin_ready,
    output wire [15:0] image_index,
    output wire [15:0] image_width,
    output wire [15:0] image_height,
    output wire        pixel_valid,
    input  wire        pixel_ready,
    output wire [18:0] pixel_addr,
    output wire [23:0] pixel_rgb,
    output wire        image_end_valid,
    input  wire        image_end_ready,
    output wire        image_abort
);
    localparam [4:0] LD_IDLE = 5'd0, LD_START = 5'd1, LD_REQ = 5'd2, LD_WAIT = 5'd3,
                     LD_FEED = 5'd4, LD_BEGIN = 5'd5, LD_BEGIN_WAIT = 5'd6,
                     LD_REL = 5'd7, LD_ADV = 5'd8, LD_FAT_REQ = 5'd9,
                     LD_FAT_WAIT = 5'd10, LD_FAT_COPY = 5'd11, LD_FAT_CHK = 5'd12,
                     LD_NEXT_CL = 5'd13, LD_END = 5'd14, LD_END_WAIT = 5'd15,
                     LD_ABORT = 5'd16, LD_ABORT_WAIT = 5'd17, LD_FAT_CAPTURE=5'd18, LD_PREFETCH=5'd19;

    localparam [7:0] E_SEL    = 8'h30,   // select_index outside the scanned range
                     E_LCHAIN = 8'h31,   // invalid cluster chain while loading a file
                     E_LSD    = 8'h32;   // block service error while loading a file

    reg [7:0] parser_byte;reg parser_byte_valid,parser_byte_last;
    wire parser_enqueue;
    // ---- index scanner ------------------------------------------------------
    wire        idx_busy, idx_done;
    wire [7:0]  idx_error;
    wire [15:0] idx_count;
    wire        idx_sec_req, idx_sec_release;
    wire [31:0] idx_sec_lba;
    wire [8:0]  idx_buf_addr;
    wire [31:0] idx_ent_cluster, idx_ent_size;
    wire [95:0] idx_ent_name;
    wire [31:0] geo_fat_lba, geo_data_lba, geo_max_cluster;
    wire [7:0]  geo_spc;
    wire [2:0]  geo_shift;
    assign audio_fat_lba=geo_fat_lba;
    assign audio_data_lba=geo_data_lba;
    assign audio_max_cluster=geo_max_cluster;
    assign audio_spc=geo_spc;assign audio_shift=geo_shift;
    assign audio_scan_error=idx_error;

    // ---- shared sector reader ------------------------------------------------
    wire        sec_req, sec_ready, sec_valid, sec_error, sec_release;
    wire [31:0] sec_lba;
    wire [8:0]  buf_addr;
    wire [7:0]  buf_data;

    // ---- parser -------------------------------------------------------------
    wire        parser_in_ready, parser_hdr_valid, parser_bottom_up;
    wire        parser_pixel_valid, parser_done, parser_abort;
    wire [15:0] parser_width, parser_height;
    wire [18:0] parser_pixel_addr;
    wire [23:0] parser_pixel_rgb;
    wire [7:0]  parser_error;

    // ---- loader state -------------------------------------------------------
    reg  [4:0]  ld_state;
    reg  [15:0] ld_sel;
    reg  [31:0] ld_size, ld_cluster, ld_bytes_left;
    reg  [7:0]  ld_sec_in_cluster;
    reg  [8:0]  ld_feed;
    reg  [7:0]  ld_fatb [0:3];
    reg  [2:0]  ld_i;
    reg         ld_begin_done;
    reg  [7:0]  ld_error;
    reg         ld_sec_req, ld_sec_release;
    reg  [31:0] ld_sec_lba;
    reg         ld_start_pulse;

    wire [31:0] ld_fat_off  = ld_cluster << 2;
    reg [31:0] ld_cluster_base;
    always @(posedge mem_clk)ld_cluster_base<=geo_data_lba+((ld_cluster-32'd2)<<geo_shift);
    wire [31:0] ld_sec_lba_w=ld_cluster_base+{24'd0,ld_sec_in_cluster};
    wire [8:0]  ld_fat_pos  = ld_fat_off[8:0];
    wire [8:0]  ld_fat_addr = ld_fat_pos + {6'd0, ld_i};
    wire [31:0] ld_fat_next = {4'b0, ld_fatb[3][3:0], ld_fatb[2], ld_fatb[1], ld_fatb[0]};
    wire        scanning    = idx_busy;

    // The sector buffer address is combinational during a load so that the byte
    // offered to the parser always matches the loader's current counter.
    wire [8:0]  ld_buf_addr = (ld_state == LD_FAT_COPY || ld_state==LD_FAT_CAPTURE) ? ld_fat_addr : ld_feed;

    assign select_ready   = idx_done && !idx_busy && (ld_state == LD_IDLE) && sec_ready;
    assign resource_count = idx_count;
    assign scan_done      = idx_done;
    assign busy           = idx_busy || (ld_state != LD_IDLE);
    assign error          = idx_error | ld_error | parser_error;

    assign sec_req     = scanning ? idx_sec_req     : ld_sec_req;
    assign sec_lba     = scanning ? idx_sec_lba     : ld_sec_lba;
    assign sec_release = scanning ? idx_sec_release : ld_sec_release;
    assign buf_addr    = scanning ? idx_buf_addr    : ld_buf_addr;

    museum_phase2_sd_sector u_sector (
        .clk(mem_clk), .rst(mem_rst),
        .req_valid(sec_req), .req_lba(sec_lba), .req_ready(sec_ready),
        .sector_valid(sec_valid), .sector_error(sec_error), .buf_release(sec_release),
        .buf_addr(buf_addr), .buf_data(buf_data),
        .rd_req_valid(rd_req_valid), .rd_lba(rd_lba), .rd_count(rd_count),
        .rd_req_ready(rd_req_ready), .rd_data(rd_data), .rd_valid(rd_valid),
        .rd_sector_commit(rd_sector_commit), .rd_done(rd_done), .rd_error(rd_error),
        .rd_resume(rd_resume)
    );

    museum_phase6_fat_index #(.MAX_ENTRIES(MAX_ENTRIES),.CACHE_AUDIO(CACHE_AUDIO)) u_index (
        .audio_raddr(audio_raddr),.audio_present(audio_present),.audio_cluster(audio_cluster),.audio_size(audio_size),
        .clk(mem_clk), .rst(mem_rst), .scan_start(scan_start),
        .count(idx_count), .done(idx_done), .busy(idx_busy), .error(idx_error),
        .ent_raddr(select_index[4:0]),
        .ent_cluster(idx_ent_cluster), .ent_size(idx_ent_size), .ent_name(idx_ent_name),
        .geo_fat_lba(geo_fat_lba), .geo_data_lba(geo_data_lba), .geo_spc(geo_spc),
        .geo_shift(geo_shift), .geo_max_cluster(geo_max_cluster),
        .sec_req(idx_sec_req), .sec_lba(idx_sec_lba), .sec_ready(sec_ready),
        .sec_valid(sec_valid && scanning), .sec_error(sec_error && scanning),
        .buf_addr(idx_buf_addr), .buf_data(buf_data), .sec_release(idx_sec_release)
    );

    assign parser_enqueue=ld_state==LD_FEED && !parser_byte_valid && !(parser_hdr_valid && !ld_begin_done);
    always @(posedge mem_clk)begin
     if(mem_rst || ld_start_pulse || image_abort)parser_byte_valid<=0;
     else begin
      if(parser_byte_valid && parser_in_ready)parser_byte_valid<=0;
      if(parser_enqueue)begin parser_byte<=buf_data;parser_byte_last<=ld_bytes_left==1;parser_byte_valid<=1;end
     end
    end
    museum_phase2_bmp_parser #(.CANVAS_WIDTH(CANVAS_WIDTH)) u_parser (
        .clk(mem_clk), .rst(mem_rst), .start(ld_start_pulse),
        .in_data(parser_byte), .in_valid(parser_byte_valid), .in_ready(parser_in_ready),
        .in_last(parser_byte_last), .in_error(1'b0),
        .hdr_valid(parser_hdr_valid), .img_width(parser_width), .img_height(parser_height),
        .bottom_up(parser_bottom_up),
        .pixel_valid(parser_pixel_valid), .pixel_ready(pixel_ready),
        .pixel_addr(parser_pixel_addr), .pixel_rgb(parser_pixel_rgb),
        .error(parser_error), .done(parser_done), .abort(parser_abort)
    );

    assign image_begin_valid = (ld_state == LD_BEGIN) || (ld_state == LD_BEGIN_WAIT);
    assign image_index       = ld_sel;
    assign image_width       = parser_width;
    assign image_height      = parser_height;
    assign pixel_valid       = parser_pixel_valid;
    assign pixel_addr        = parser_pixel_addr;
    assign pixel_rgb         = parser_pixel_rgb;
    assign image_end_valid   = (ld_state == LD_END_WAIT);
    assign image_abort       = (ld_state == LD_ABORT_WAIT);

    always @(posedge mem_clk) begin
        if (mem_rst) begin
            ld_state <= LD_IDLE; ld_sel <= 16'd0; ld_size <= 32'd0; ld_cluster <= 32'd0;
            ld_bytes_left <= 32'd0; ld_sec_in_cluster <= 8'd0; ld_feed <= 9'd0;
            ld_i <= 3'd0; ld_begin_done <= 1'b0; ld_error <= 8'd0;
            ld_sec_req <= 1'b0; ld_sec_release <= 1'b0; ld_sec_lba <= 32'd0;
            ld_start_pulse <= 1'b0;
        end else begin
            ld_start_pulse <= 1'b0;
            case (ld_state)
                LD_IDLE: begin
                    ld_sec_req <= 1'b0;
                    // INTERFACES_V1 section 6: an error is held until the next
                    // master request or reset, so it must not be cleared here.
                    if (select_valid && idx_done && !idx_busy && sec_ready) begin
                        ld_error <= 8'd0;
                        if (select_index >= idx_count) begin
                            ld_error <= E_SEL;
                            ld_state <= LD_ABORT;
                        end else begin
                            ld_sel        <= select_index;
                            ld_size       <= idx_ent_size;
                            ld_cluster    <= idx_ent_cluster;
                            ld_begin_done <= 1'b0;
                            ld_state      <= LD_START;
                        end
                    end
                end

                LD_START: begin
                    ld_start_pulse    <= 1'b1;
                    ld_bytes_left     <= ld_size;
                    ld_sec_in_cluster <= 8'd0;
                    ld_feed           <= 9'd0;
                    ld_state          <= LD_REQ;
                end

                LD_REQ: begin
                    ld_sec_lba <= ld_sec_lba_w;
                    ld_sec_req <= 1'b1;
                    ld_state   <= LD_WAIT;
                end

                LD_WAIT: begin
                    if (sec_error && !scanning) begin
                        ld_error <= E_LSD;
                        ld_state <= LD_ABORT;
                    end else if (sec_valid && !scanning) begin
                        ld_sec_req <= 1'b0;
                        ld_feed    <= 9'd0;
                        ld_state   <= LD_PREFETCH;
                    end
                end

                LD_PREFETCH: ld_state<=LD_FEED;
                LD_FEED: begin
                    if (parser_hdr_valid && !ld_begin_done) begin
                        ld_state <= LD_BEGIN;
                    end else if (parser_enqueue) begin
                        if (ld_bytes_left == 32'd1) begin
                            // the parser has taken the final byte of the file
                            ld_bytes_left <= 32'd0;
                            ld_state      <= LD_REL;
                        end else if (ld_feed == 9'd511) begin
                            ld_bytes_left <= ld_bytes_left - 32'd1;
                            ld_state      <= LD_REL;
                        end else begin
                            ld_bytes_left <= ld_bytes_left - 32'd1;
                            ld_feed       <= ld_feed + 9'd1;
                        end
                    end
                end

                LD_BEGIN: if (image_begin_ready) begin
                    ld_begin_done <= 1'b1;
                    ld_state      <= LD_FEED;
                end else begin
                    ld_state <= LD_BEGIN_WAIT;
                end

                LD_BEGIN_WAIT: if (image_begin_ready) begin
                    ld_begin_done <= 1'b1;
                    ld_state      <= LD_FEED;
                end

                LD_REL: begin
                    ld_sec_release <= 1'b1;
                    ld_state       <= LD_ADV;
                end

                LD_ADV: begin
                    ld_sec_release <= 1'b0;
                    if (ld_bytes_left == 32'd0) begin
                        ld_state <= LD_END;
                    end else if (ld_sec_in_cluster + 8'd1 < geo_spc) begin
                        ld_sec_in_cluster <= ld_sec_in_cluster + 8'd1;
                        ld_state          <= LD_REQ;
                    end else begin
                        ld_i     <= 3'd0;
                        ld_state <= LD_FAT_REQ;
                    end
                end

                LD_FAT_REQ: begin
                    ld_sec_lba <= geo_fat_lba + (ld_fat_off >> 9);
                    ld_sec_req <= 1'b1;
                    ld_state   <= LD_FAT_WAIT;
                end

                LD_FAT_WAIT: begin
                    if (sec_error && !scanning) begin
                        ld_error <= E_LSD;
                        ld_state <= LD_ABORT;
                    end else if (sec_valid && !scanning) begin
                        ld_sec_req <= 1'b0;
                        ld_i       <= 3'd0;
                        ld_state   <= LD_FAT_COPY;
                    end
                end

                LD_FAT_COPY: ld_state<=LD_FAT_CAPTURE;
                LD_FAT_CAPTURE: begin
                    ld_fatb[ld_i] <= buf_data;
                    if (ld_i == 3'd3) ld_state <= LD_FAT_CHK;
                    else begin ld_i<=ld_i+3'd1;ld_state<=LD_FAT_COPY;end
                end

                LD_FAT_CHK: begin
                    ld_sec_release <= 1'b1;
                    if (ld_fat_next < 32'd2 || ld_fat_next >= geo_max_cluster ||
                        ld_fat_next >= 32'h0ffffff0 || ld_fat_next == ld_cluster) begin
                        ld_error <= E_LCHAIN;
                        ld_state <= LD_ABORT;
                    end else begin
                        ld_cluster        <= ld_fat_next;
                        ld_sec_in_cluster <= 8'd0;
                        ld_state          <= LD_NEXT_CL;
                    end
                end

                LD_NEXT_CL: begin
                    ld_sec_release <= 1'b0;
                    ld_state       <= LD_REQ;
                end

                LD_END: begin
                    if (parser_done)          ld_state <= LD_END_WAIT;
                    else if (parser_error != 8'd0) ld_state <= LD_ABORT;
                end

                LD_END_WAIT: if (image_end_ready) ld_state <= LD_IDLE;

                LD_ABORT: begin
                    ld_sec_req     <= 1'b0;
                    ld_sec_release <= 1'b1;
                    ld_state       <= LD_ABORT_WAIT;
                end

                LD_ABORT_WAIT: if (sec_ready) begin
                    ld_sec_release <= 1'b0;
                    ld_state       <= LD_IDLE;
                end

                default: ld_state <= LD_IDLE;
            endcase
        end
    end
endmodule

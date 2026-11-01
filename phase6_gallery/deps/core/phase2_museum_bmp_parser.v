// museum_phase2_bmp_parser: parse one uncompressed 24-bit BMP byte stream and emit
// RGB888 pixels addressed by normalized top-left canvas coordinates.
// Child of museum_phase2_resources; INTERFACES_V1 sections 4 (resources) and 6 (pixels).
// Verilog-2001 synthesizable subset, 100 MHz memory domain, sync active-high reset.
//
// The consumer must terminate every file with either in_last on the final byte
// or in_error; a stream that simply stops leaves the parser waiting.
module museum_phase2_bmp_parser #(
    parameter integer CANVAS_WIDTH = 640,
    parameter integer MAX_WIDTH    = 640,
    parameter integer MAX_HEIGHT   = 480
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,        // one-cycle pulse: begin a new file
    input  wire [7:0]  in_data,
    input  wire        in_valid,
    output wire        in_ready,
    input  wire        in_last,      // asserted with the final byte of the file
    input  wire        in_error,     // stream could not be delivered (SD/FAT/CRC)
    output reg         hdr_valid,    // geometry below is meaningful
    output reg  [15:0] img_width,
    output reg  [15:0] img_height,
    output reg         bottom_up,
    output reg         pixel_valid,
    input  wire        pixel_ready,
    output reg  [18:0] pixel_addr,   // y*CANVAS_WIDTH + x, 0..CANVAS_WIDTH*MAX_HEIGHT-1
    output reg  [23:0] pixel_rgb,    // {R,G,B}
    output reg  [7:0]  error,        // sticky; 0 while healthy
    output reg         done,         // sticky; file parsed and all pixels accepted
    output reg         abort         // one-cycle pulse on the first error
);
    localparam [15:0] MAXW = MAX_WIDTH;
    localparam [15:0] MAXH = MAX_HEIGHT;

    localparam [3:0] ST_SIG   = 4'd0,
                     ST_HDR   = 4'd1,
                     ST_CHECK = 4'd2,
                     ST_SETUP = 4'd3,
                     ST_SKIP  = 4'd4,
                     ST_PIX   = 4'd5,
                     ST_TAIL  = 4'd6,
                     ST_DONE  = 4'd7,
                     ST_HALT  = 4'd8;

    localparam [7:0] E_BPP    = 8'h41,   // bit depth other than 24
                     E_COMP   = 8'h42,   // compressed
                     E_SIG    = 8'h43,   // not "BM"
                     E_DIB    = 8'h44,   // DIB header too small
                     E_DIM    = 8'h45,   // width/height zero, negative width or over limit
                     E_PLANES = 8'h46,   // planes != 1
                     E_OFFSET = 8'h47,   // pixel offset inconsistent with headers
                     E_STREAM = 8'h48,   // upstream reported a delivery error
                     E_TRUNC  = 8'h49;   // file ended before the expected pixels

    reg [3:0]  state;
    reg [23:0] idx;
    reg [31:0] f_size, f_off, f_dib, f_w, f_h, f_comp;
    reg [15:0] f_planes, f_bpp;
    reg [15:0] row, px_x, pad_left;
    reg [1:0]  chan;
    reg [7:0]  b_reg, g_reg;
    reg        in_pad, last_seen;

    reg [18:0] row_base;
    wire [31:0] w3        = {16'd0, img_width} * 32'd3;
    wire [31:0] stride_w  = ((w3 + 32'd3) >> 2) << 2;
    wire [15:0] pad_w     = stride_w[15:0] - w3[15:0];
    wire [15:0] row_y     = bottom_up ? (img_height - 16'd1 - row) : row;
    wire [31:0] y_base    = row_y * CANVAS_WIDTH;
    wire [18:0] addr_next = row_base + {9'd0, px_x[9:0]};
    wire        byte_fire = in_valid && in_ready;

    assign in_ready = (state == ST_SIG || state == ST_HDR || state == ST_SKIP ||
                       state == ST_PIX || state == ST_TAIL) &&
                      !pixel_valid && (error == 8'd0);

    task fail;
        input [7:0] code;
        begin
            error       <= code;
            abort       <= 1'b1;
            pixel_valid <= 1'b0;
            done        <= 1'b0;
            state       <= ST_HALT;
        end
    endtask

    task accumulate;
        input [23:0] off;
        input [7:0]  d;
        begin
            case (off)
                24'd2:  f_size[7:0]     <= d;
                24'd3:  f_size[15:8]    <= d;
                24'd4:  f_size[23:16]   <= d;
                24'd5:  f_size[31:24]   <= d;
                24'd10: f_off[7:0]      <= d;
                24'd11: f_off[15:8]     <= d;
                24'd12: f_off[23:16]    <= d;
                24'd13: f_off[31:24]    <= d;
                24'd14: f_dib[7:0]      <= d;
                24'd15: f_dib[15:8]     <= d;
                24'd16: f_dib[23:16]    <= d;
                24'd17: f_dib[31:24]    <= d;
                24'd18: f_w[7:0]        <= d;
                24'd19: f_w[15:8]       <= d;
                24'd20: f_w[23:16]      <= d;
                24'd21: f_w[31:24]      <= d;
                24'd22: f_h[7:0]        <= d;
                24'd23: f_h[15:8]       <= d;
                24'd24: f_h[23:16]      <= d;
                24'd25: f_h[31:24]      <= d;
                24'd26: f_planes[7:0]   <= d;
                24'd27: f_planes[15:8]  <= d;
                24'd28: f_bpp[7:0]      <= d;
                24'd29: f_bpp[15:8]     <= d;
                24'd30: f_comp[7:0]     <= d;
                24'd31: f_comp[15:8]    <= d;
                24'd32: f_comp[23:16]   <= d;
                24'd33: f_comp[31:24]   <= d;
                default: ;
            endcase
        end
    endtask

    reg [31:0] hdr_hmag,hdr_bytes,hdr_end,hdr_min;
    reg [23:0] skip_final_index;
    reg [15:0] hdr_stride;reg [18:0] initial_base;
    reg bad_width,bad_height;
    always @(posedge clk)begin
     // f_off settles by header byte 13, well before ST_SKIP. Precompute
     // the boundary instead of a 24-bit increment on the state-enable path.
     skip_final_index<=f_off[23:0]-24'd1;
     hdr_hmag<=f_h[31] ? (~f_h+32'd1) : f_h;
     hdr_stride<=((f_w[15:0]*16'd3+16'd3)>>2)<<2;
     hdr_bytes<=hdr_stride[11:0]*hdr_hmag[15:0];
     hdr_end<=f_off+hdr_bytes;hdr_min<=32'd14+f_dib;
     bad_width<=f_w[31:16]!=0 || f_w[15:0]==0 || f_w[15:0]>MAXW;
     bad_height<=hdr_hmag[31:16]!=0 || hdr_hmag[15:0]==0 || hdr_hmag[15:0]>MAXH;
     initial_base<=(hdr_hmag[15:0]-16'd1)*19'd640;
    end
    task check_header;
        reg [31:0] hmag, w3h, strideh;
        begin
            w3h=0;
            strideh=hdr_stride;
            hmag=hdr_hmag;
            if (f_dib < 32'd40)
                fail(E_DIB);
            else if (f_planes != 16'd1)
                fail(E_PLANES);
            else if (f_bpp != 16'd24)
                fail(E_BPP);
            else if (f_comp != 32'd0)
                fail(E_COMP);
            else if (bad_width)
                fail(E_DIM);
            else if (bad_height)
                fail(E_DIM);
            else if (f_off < hdr_min || f_off[31:24] != 8'd0)
                fail(E_OFFSET);
            else if (f_size != 32'd0 && hdr_end > f_size)
                fail(E_TRUNC);
            else begin
                img_width  <= f_w[15:0];
                img_height <= hmag[15:0];
                bottom_up  <= ~f_h[31];   // positive height means the rows are stored bottom-up
                hdr_valid  <= 1'b1;
            end
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            state <= ST_SIG; idx <= 24'd0;
            f_size <= 0; f_off <= 0; f_dib <= 0; f_w <= 0; f_h <= 0; f_comp <= 0;
            f_planes <= 0; f_bpp <= 0;
            row <= 0; px_x <= 0; pad_left <= 0; chan <= 0; b_reg <= 0; g_reg <= 0;
            in_pad <= 1'b0; last_seen <= 1'b0;
            hdr_valid <= 1'b0; img_width <= 0; img_height <= 0; bottom_up <= 1'b0;
            pixel_valid <= 1'b0; pixel_addr <= 0; pixel_rgb <= 0;
            error <= 8'd0; done <= 1'b0; abort <= 1'b0;
        end else begin
            abort <= 1'b0;
            if (start) begin
                state <= ST_SIG; idx <= 24'd0;
                f_size <= 0; f_off <= 0; f_dib <= 0; f_w <= 0; f_h <= 0; f_comp <= 0;
                f_planes <= 0; f_bpp <= 0;
                row <= 0; px_x <= 0; pad_left <= 0; chan <= 0;
                in_pad <= 1'b0; last_seen <= 1'b0;
                hdr_valid <= 1'b0; img_width <= 0; img_height <= 0; bottom_up <= 1'b0;
                pixel_valid <= 1'b0; error <= 8'd0; done <= 1'b0;
            end else begin
                if (pixel_valid && pixel_ready)
                    pixel_valid <= 1'b0;

                if (error != 8'd0)
                    state <= ST_HALT;
                else if (in_error)
                    fail(E_STREAM);
                else if (last_seen && state != ST_TAIL && state != ST_DONE)
                    fail(E_TRUNC);
                else begin
                    case (state)
                        ST_SIG: if (byte_fire) begin
                            idx <= idx + 24'd1;
                            if ((idx == 24'd0 && in_data != 8'h42) ||
                                (idx == 24'd1 && in_data != 8'h4d))
                                fail(E_SIG);
                            else if (idx == 24'd1)
                                state <= ST_HDR;
                        end

                        ST_HDR: if (byte_fire) begin
                            accumulate(idx, in_data);
                            idx <= idx + 24'd1;
                            if (idx == 24'd37)
                                state <= ST_CHECK;
                        end

                        ST_CHECK: begin
                            check_header();
                            state <= ST_SETUP;
                        end

                        ST_SETUP: begin
                            row_base<=bottom_up ? initial_base : 19'd0;
                            row <= 16'd0; px_x <= 16'd0; chan <= 2'd0;
                            in_pad <= 1'b0; pad_left <= pad_w;
                            if (idx == f_off[23:0])
                                state <= ST_PIX;
                            else
                                state <= ST_SKIP;
                        end

                        ST_SKIP: if (byte_fire) begin
                            idx <= idx + 24'd1;
                            if (idx == skip_final_index) begin
                                state <= ST_PIX;
                                row <= 16'd0; px_x <= 16'd0; chan <= 2'd0;
                                in_pad <= 1'b0; pad_left <= pad_w;
                            end
                        end

                        ST_PIX: if (byte_fire) begin
                            idx <= idx + 24'd1;
                            if (in_last)
                                last_seen <= 1'b1;
                            if (in_pad) begin
                                if (pad_left <= 16'd1) begin
                                    in_pad <= 1'b0;
                                    if (row + 16'd1 == img_height)
                                        state <= ST_TAIL;
                                    else begin
                                        row <= row + 16'd1;row_base<=bottom_up ? row_base-19'd640 : row_base+19'd640; px_x <= 16'd0;
                                        chan <= 2'd0; pad_left <= pad_w;
                                    end
                                end else
                                    pad_left <= pad_left - 16'd1;
                            end else begin
                                case (chan)
                                    2'd0: begin
                                        b_reg <= in_data;
                                        chan  <= 2'd1;
                                    end
                                    2'd1: begin
                                        g_reg <= in_data;
                                        chan  <= 2'd2;
                                    end
                                    default: begin
                                        pixel_rgb   <= {in_data, g_reg, b_reg};
                                        pixel_addr  <= addr_next;
                                        pixel_valid <= 1'b1;
                                        chan        <= 2'd0;
                                        if (px_x + 16'd1 == img_width) begin
                                            px_x <= 16'd0;
                                            if (pad_w != 16'd0) begin
                                                in_pad   <= 1'b1;
                                                pad_left <= pad_w;
                                            end else if (row + 16'd1 == img_height) begin
                                                state <= ST_TAIL;
                                            end else begin
                                                row <= row + 16'd1;row_base<=bottom_up ? row_base-19'd640 : row_base+19'd640;
                                            end
                                        end else begin
                                            px_x <= px_x + 16'd1;
                                        end
                                    end
                                endcase
                            end
                        end

                        ST_TAIL: begin
                            if (byte_fire && in_last)
                                last_seen <= 1'b1;
                            if (last_seen && !pixel_valid) begin
                                done  <= 1'b1;
                                state <= ST_DONE;
                            end
                        end

                        ST_DONE, ST_HALT: ;
                        default: state <= ST_HALT;
                    endcase
                end
            end
        end
    end
endmodule

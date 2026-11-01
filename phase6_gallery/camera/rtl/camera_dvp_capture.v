// Source-synchronous 8-bit DVP receiver; all ports belong to the PCLK domain.
// VSYNC is active high blanking by default; HREF is active high valid data.
// Pixels are provisional: only frame_done && frame_good permits a frame commit.
// A consumer must discard the entire frame after any error/overflow. No backpressure.
module camera_dvp_capture #(
    parameter integer WIDTH=320,
    parameter integer HEIGHT=240,
    parameter VSYNC_ACTIVE=1'b1,
    parameter BYTE_SWAP=1'b0
)(
    input wire pclk, rst,
    input wire vsync, href,
    input wire [7:0] data,
    input wire overflow,
    output reg pixel_valid,
    output reg [15:0] pixel,
    output reg [15:0] pixel_x, pixel_y,
    output reg frame_start, frame_done, frame_good,
    // Error bits: 0=line length, 1=line count, 2=sync during line, 3=overflow.
    output reg [3:0] frame_error,
    output reg [15:0] observed_lines, observed_line_bytes,
    output reg [31:0] good_frames, bad_frames
);
    localparam integer EXPECT_BYTES=WIDTH*2;
    localparam integer BCW=$clog2(EXPECT_BYTES+2);
    localparam integer LCW=$clog2(HEIGHT+2);
    reg [BCW-1:0] line_bytes, last_line_bytes;
    reg [LCW-1:0] lines;
    reg [7:0] first_byte;
    reg byte_phase, prev_href, prev_sync, armed;
    reg [3:0] errors;
    wire sync_active=(vsync==VSYNC_ACTIVE);
    wire sync_rise=sync_active && !prev_sync;
    always @(posedge pclk) begin
        if (rst) begin
            pixel_valid<=0; pixel<=0; pixel_x<=0; pixel_y<=0;
            frame_start<=0; frame_done<=0; frame_good<=0; frame_error<=0;
            observed_lines<=0; observed_line_bytes<=0;
            good_frames<=0; bad_frames<=0;
            line_bytes<=0; last_line_bytes<=0; lines<=0;
            first_byte<=0; byte_phase<=0; prev_href<=0; prev_sync<=0;
            armed<=0; errors<=0;
        end else begin
            prev_sync<=sync_active;
            prev_href<=href && !sync_active;
            pixel_valid<=0; frame_start<=0; frame_done<=0; frame_good<=0;
            if (sync_rise) begin
                // HREF must end before VSYNC; simultaneous edges are rejected.
                if (armed) begin
                    frame_done<=1;
                    observed_lines<=lines;
                    observed_line_bytes<=prev_href ? line_bytes : last_line_bytes;
                    frame_error<=errors | ((lines!=HEIGHT) ? 4'b0010 : 4'b0000)
                        | ((prev_href || href) ? 4'b0100 : 4'b0000)
                        | (overflow ? 4'b1000 : 4'b0000);
                    if (errors==0 && lines==HEIGHT && !prev_href && !href && !overflow) begin
                        frame_good<=1; good_frames<=good_frames+1'b1;
                    end else bad_frames<=bad_frames+1'b1;
                end
                armed<=1; frame_start<=1; errors<=0;
                lines<=0; line_bytes<=0; last_line_bytes<=0; byte_phase<=0;
            end else if (armed && !sync_active) begin
                if (overflow) errors[3]<=1;
                if (href) begin
                    if (line_bytes<EXPECT_BYTES+1) line_bytes<=line_bytes+1'b1;
                    if (line_bytes>=EXPECT_BYTES) errors[0]<=1;
                    if (lines>=HEIGHT) errors[1]<=1;
                    byte_phase<=~byte_phase;
                    if (!byte_phase) first_byte<=data;
                    else if (errors==0 && !overflow && line_bytes<EXPECT_BYTES && lines<HEIGHT) begin
                        pixel<=BYTE_SWAP ? {data,first_byte} : {first_byte,data};
                        pixel_x<=line_bytes>>1; pixel_y<=lines;
                        pixel_valid<=1;
                    end
                end else if (prev_href) begin
                    last_line_bytes<=line_bytes;
                    if (line_bytes!=EXPECT_BYTES || byte_phase) errors[0]<=1;
                    if (lines<HEIGHT+1) lines<=lines+1'b1;
                    if (lines>=HEIGHT) errors[1]<=1;
                    line_bytes<=0; byte_phase<=0;
                end
            end
        end
    end
endmodule

// Two complete decimated RGB565 frames. Source cannot be backpressured.
// A single toggle both publishes a frame and encodes its bank (~offer_toggle).
// Writer waits for VBLANK acknowledgement before reusing the previous display bank.
module camera_preview_buffer #(
    parameter integer INPUT_WIDTH=320,INPUT_HEIGHT=240,DECIMATE_BITS=2,
    parameter integer WIDTH=INPUT_WIDTH>>DECIMATE_BITS,HEIGHT=INPUT_HEIGHT>>DECIMATE_BITS,
    parameter integer PIXELS=WIDTH*HEIGHT,ADDR_W=$clog2(PIXELS),
    parameter RAM_STYLE="bram_9k"
)(
    input wire wr_clk,wr_rst,pixel_valid,frame_start,frame_done,frame_good,
    input wire [15:0] pixel,pixel_x,pixel_y,
    input wire rd_clk,rd_rst,vblank,
    input wire [ADDR_W-1:0] rd_addr,
    output wire [15:0] rd_pixel,output reg have_frame,
    output reg [31:0] published_frames,skipped_frames,
    output reg displayed_frame_update
);
    reg offer_toggle,display_ack;
    (* async_reg="true" *) reg [1:0] ack_sync,offer_sync;
    reg writing,display_bank,awaiting_pixels;
    reg [ADDR_W:0] samples;
    wire [15:0] q0,q1;
    wire pending=offer_toggle!=ack_sync[1];
    wire publish=writing && frame_done && frame_good && samples==PIXELS;
    // VSYNC publishes the previous frame before active pixels of the next.
    // Decide at the first pixel, allowing an ACK during vertical blank.
    // Once that first pixel is lost, never join a frame partway through.
    wire admit=awaiting_pixels && pixel_valid && !pending && !frame_start;
    wire sample=pixel_valid && (writing || admit) && !pending && !frame_start &&
        pixel_x[DECIMATE_BITS-1:0]==0 && pixel_y[DECIMATE_BITS-1:0]==0 && samples<PIXELS;
    camera_preview_bank #(.PIXELS(PIXELS),.RAM_STYLE(RAM_STYLE)) bank0(
        .wr_clk(wr_clk),.we(sample && !wr_rst && !offer_toggle),.wr_addr(samples[ADDR_W-1:0]),.pixel(pixel),
        .rd_clk(rd_clk),.rd_addr(rd_addr),.q(q0));
    camera_preview_bank #(.PIXELS(PIXELS),.RAM_STYLE(RAM_STYLE)) bank1(
        .wr_clk(wr_clk),.we(sample && !wr_rst && offer_toggle),.wr_addr(samples[ADDR_W-1:0]),.pixel(pixel),
        .rd_clk(rd_clk),.rd_addr(rd_addr),.q(q1));
    assign rd_pixel=display_bank ? q1 : q0;
    always @(posedge wr_clk or posedge wr_rst)begin
        if(wr_rst)begin offer_toggle<=0;ack_sync<=0;writing<=0;awaiting_pixels<=0;samples<=0;published_frames<=0;skipped_frames<=0;end
        else begin
            ack_sync<={ack_sync[0],display_ack};
            if(sample)samples<=samples+1'b1;
            if(frame_start)begin
                writing<=0;awaiting_pixels<=1;samples<=0;
            end else if(awaiting_pixels && pixel_valid)begin
                awaiting_pixels<=0;writing<=!pending;
                if(pending)skipped_frames<=skipped_frames+1'b1;
            end
            if(publish)begin offer_toggle<=~offer_toggle;writing<=0;published_frames<=published_frames+1'b1;end
        end
    end
    always @(posedge rd_clk or posedge rd_rst)begin
        if(rd_rst)begin offer_sync<=0;display_ack<=0;display_bank<=0;have_frame<=0;displayed_frame_update<=0;end
        else begin
            displayed_frame_update<=0;
            offer_sync<={offer_sync[0],offer_toggle};
            if(vblank && offer_sync[1]!=display_ack)begin
                display_bank<=!offer_sync[1];display_ack<=offer_sync[1];have_frame<=1;displayed_frame_update<=1;
            end
        end
    end
endmodule

// Split 19200 pixels at a power-of-two boundary to avoid rounding each bank
// to 32768 words. Use 32K blocks for the prefix and 9K blocks for the tail.
// Both paths retain the same single-cycle synchronous read latency.
module camera_preview_bank #(
    parameter integer PIXELS=4800,ADDR_W=$clog2(PIXELS),SPLIT=16384,
    parameter RAM_STYLE="bram_9k"
)(input wire wr_clk,we,input wire [ADDR_W-1:0] wr_addr,input wire [15:0] pixel,
  input wire rd_clk,input wire [ADDR_W-1:0] rd_addr,output wire [15:0] q);
    generate if(PIXELS>SPLIT)begin: mixed
        localparam TAIL=PIXELS-SPLIT,TAIL_AW=$clog2(TAIL);
        (* ram_style="bram_32k" *) reg [15:0] head[0:SPLIT-1];
        (* ram_style="bram_9k" *) reg [15:0] tail[0:TAIL-1];
        reg [15:0] head_q,tail_q;
        reg tail_select;
        wire [TAIL_AW-1:0] tail_wr=wr_addr-SPLIT,tail_rd=rd_addr-SPLIT;
        always @(posedge wr_clk)if(we)begin
            if(wr_addr<SPLIT)head[wr_addr[$clog2(SPLIT)-1:0]]<=pixel;
            else tail[tail_wr]<=pixel;
        end
        always @(posedge rd_clk)begin
            head_q<=head[rd_addr[$clog2(SPLIT)-1:0]];
            tail_q<=tail[tail_rd];tail_select<=rd_addr>=SPLIT;
        end
        assign q=tail_select ? tail_q : head_q;
    end else begin: simple
        (* ram_style=RAM_STYLE *) reg [15:0] mem[0:PIXELS-1];
        reg [15:0] rd_q;
        always @(posedge wr_clk)if(we)mem[wr_addr]<=pixel;
        always @(posedge rd_clk)rd_q<=mem[rd_addr];
        assign q=rd_q;
    end endgenerate
endmodule

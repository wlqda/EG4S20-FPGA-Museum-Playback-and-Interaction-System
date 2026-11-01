// Evaluate both VSYNC polarities against exact geometry; lock after 3 consecutive valid frames.
// No frame-size checks are relaxed and the selected polarity remains fixed until reset.
module camera_dvp_auto_monitor #(parameter integer WIDTH=320,HEIGHT=240,parameter BYTE_SWAP=0)(
    input wire pclk,rst,vsync,href,input wire [7:0] data,
    output reg locked,low_active,output wire [147:0] stats,
    output wire pixel_valid,frame_start,frame_done,frame_good,
    output wire [15:0] pixel,pixel_x,pixel_y
);
    wire [147:0] high_stats,low_stats;
    wire [3:0] high_events,low_events;
    wire [15:0] high_pixel,high_x,high_y,low_pixel,low_x,low_y;
    camera_dvp_frame_monitor #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.VSYNC_ACTIVE(1),.BYTE_SWAP(BYTE_SWAP)) high_monitor(
        .pclk(pclk),.rst(rst),.vsync(vsync),.href(href),.data(data),.stats(high_stats),
        .pixel_valid(high_events[0]),.frame_start(high_events[1]),.frame_done(high_events[2]),.frame_good(high_events[3]),
        .pixel(high_pixel),.pixel_x(high_x),.pixel_y(high_y));
    camera_dvp_frame_monitor #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.VSYNC_ACTIVE(0),.BYTE_SWAP(BYTE_SWAP)) low_monitor(
        .pclk(pclk),.rst(rst),.vsync(vsync),.href(href),.data(data),.stats(low_stats),
        .pixel_valid(low_events[0]),.frame_start(low_events[1]),.frame_done(low_events[2]),.frame_good(low_events[3]),
        .pixel(low_pixel),.pixel_x(low_x),.pixel_y(low_y));
    always @(posedge pclk or posedge rst)begin
        if(rst)begin locked<=0;low_active<=0;end
        else if(!locked)begin
            if(high_stats[31:0]>=3)begin locked<=1;low_active<=0;end
            else if(low_stats[31:0]>=3)begin locked<=1;low_active<=1;end
        end
    end
    assign stats=low_active ? low_stats : high_stats;
    assign {frame_good,frame_done,frame_start,pixel_valid}=locked ? (low_active ? low_events : high_events) : 4'b0000;
    assign pixel=low_active ? low_pixel : high_pixel;
    assign pixel_x=low_active ? low_x : high_x;
    assign pixel_y=low_active ? low_y : high_y;
endmodule

module camera_dvp_frame_monitor #(parameter integer WIDTH=320,HEIGHT=240,VSYNC_ACTIVE=1,parameter BYTE_SWAP=0)(
    input wire pclk,rst,vsync,href,input wire [7:0] data,
    output reg [147:0] stats,
    output wire pixel_valid,frame_start,frame_done,frame_good,
    output wire [15:0] pixel,pixel_x,pixel_y
);
    wire [15:0] lines,bytes;
    wire [3:0] error;
    wire [31:0] good,bad;
    reg [31:0] consecutive;
    reg [15:0] checksum;
    wire [31:0] next_consecutive=frame_good ? (consecutive<1000 ? consecutive+1'b1 : consecutive) : 32'd0;
    camera_dvp_capture #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.VSYNC_ACTIVE(VSYNC_ACTIVE),.BYTE_SWAP(BYTE_SWAP)) capture(
        .pclk(pclk),.rst(rst),.vsync(vsync),.href(href),.data(data),.overflow(1'b0),
        .pixel_valid(pixel_valid),.pixel(pixel),.pixel_x(pixel_x),.pixel_y(pixel_y),
        .frame_start(frame_start),.frame_done(frame_done),.frame_good(frame_good),
        .frame_error(error),.observed_lines(lines),.observed_line_bytes(bytes),.good_frames(good),.bad_frames(bad));
    always @(posedge pclk or posedge rst)begin
        if(rst)begin stats<=0;consecutive<=0;checksum<=0;end
        else begin
            if(frame_start)checksum<=0;
            else if(pixel_valid)checksum<=checksum+pixel;
            if(frame_done)begin consecutive<=next_consecutive;stats<={good,bad,lines,bytes,error,checksum,next_consecutive};end
        end
    end
endmodule

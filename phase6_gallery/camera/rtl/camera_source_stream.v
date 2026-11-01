// Complete source frames, independent of preview ownership. Boundary tokens
// close the previous frame and open the next; RESET tokens abandon partial data.
module camera_source_stream #(
    parameter integer INPUT_WIDTH=320,INPUT_HEIGHT=240,DECIMATE_BITS=2,
    parameter integer GW=INPUT_WIDTH>>DECIMATE_BITS,GH=INPUT_HEIGHT>>DECIMATE_BITS,
    parameter integer FIFO_BITS=11,WAIT_LIMIT=40000
)(input wire wr_clk,wr_rst,pixel_valid,frame_start,frame_done,frame_good,
  input wire [15:0] pixel,pixel_x,pixel_y,
  input wire rd_clk,rd_rst,recalibrate,processing_done,
  output reg de,fresh_frame,abort_frame,
  output reg [9:0] x,y,output reg [23:0] rgb,
  output wire stream_fault);
    wire sample=pixel_valid && pixel_x[DECIMATE_BITS-1:0]==0 && pixel_y[DECIMATE_BITS-1:0]==0;
    reg synchronized,write_fault;
    wire full,empty;
    wire write_request=frame_start || (synchronized && sample);
    wire [17:0] write_data=frame_start ?
        {(synchronized && frame_done && frame_good ? 2'b01 : 2'b11),16'd0} : {2'b00,pixel};
    always @(posedge wr_clk or posedge wr_rst)begin
        if(wr_rst)begin synchronized<=0;write_fault<=0;end
        else if(write_request && full)begin synchronized<=0;write_fault<=1;end
        else if(frame_start)synchronized<=1;
    end
    localparam FETCH=0,CONSUME=1,WAIT_RESULT=2;
    reg [1:0] state;
    wire pop=state==FETCH && !empty;
    wire [17:0] data;
    camera_source_fifo #(.ABITS(FIFO_BITS)) fifo(
        .wr_clk(wr_clk),.wr_rst(wr_rst),.push(write_request && !full),.data_in(write_data),.full(full),
        .rd_clk(rd_clk),.rd_rst(rd_rst),.pop(pop),.data_out(data),.empty(empty));
    reg frame_open,flushing,read_fault;
    reg analyze_frame;
    reg [12:0] count;
    reg [6:0] column;
    reg [5:0] row;
    reg [15:0] wait_count;
    (* async_reg="true" *) reg [1:0] fault_sync;
    assign stream_fault=fault_sync[1] || read_fault;
    always @(posedge rd_clk)begin
        de<=0;fresh_frame<=0;abort_frame<=0;
        if(rd_rst)begin
            state<=FETCH;frame_open<=0;flushing<=1;count<=0;column<=0;row<=0;
            analyze_frame<=0;wait_count<=0;read_fault<=0;fault_sync<=0;x<=0;y<=0;rgb<=0;
        end else begin
            fault_sync<={fault_sync[0],write_fault};
            // Preparation must keep draining camera traffic. The previous
            // implementation blocked pop for two seconds and overflowed the FIFO.
            // Preview continues; only complete post-preparation frames await analysis.
            if(recalibrate)analyze_frame<=0;
            case(state)
                FETCH:if(!empty)state<=CONSUME;
                CONSUME:begin
                    state<=FETCH;
                    if(data[17:16]!=0)begin
                        frame_open<=1;flushing<=0;count<=0;column<=0;row<=0;
                        if(!flushing && frame_open && data[17:16]==1 && count==GW*GH)begin
                            // Non-sampled last raster coordinate closes the
                            // sparse frame after all 80x60 cells have arrived.
                            de<=1;x<=GW*8-1;y<=GH*8-1;rgb<=0;
                            if(analyze_frame && !recalibrate)begin state<=WAIT_RESULT;wait_count<=0;end
                        end else abort_frame<=1;
                    end else if(!flushing && frame_open)begin
                        if(count<GW*GH)begin
                            de<=1;fresh_frame<=count==0;
                            if(count==0)analyze_frame<=!recalibrate;
                            x<={column,3'b000};y<={1'b0,row,3'b000};
                            rgb<={data[15:11],data[15:13],data[10:5],data[10:9],data[4:0],data[4:2]};
                            count<=count+1'b1;
                            if(column==GW-1)begin column<=0;row<=row+1'b1;end else column<=column+1'b1;
                        end else begin flushing<=1;abort_frame<=1;read_fault<=1;end
                    end
                end
                WAIT_RESULT:begin
                    if(processing_done || recalibrate)state<=FETCH;
                    else if(wait_count==WAIT_LIMIT-1)begin
                        state<=FETCH;abort_frame<=1;read_fault<=1;
                    end else wait_count<=wait_count+1'b1;
                end
                default:begin state<=FETCH;flushing<=1;abort_frame<=1;read_fault<=1;end
            endcase
        end
    end
endmodule

// Dual-clock FIFO: Gray pointers cross through two synchronizers. Data is read
// synchronously; the consumer waits one cycle after pop before using data_out.
module camera_source_fifo #(parameter integer ABITS=11)(
    input wire wr_clk,wr_rst,push,input wire [17:0] data_in,output wire full,
    input wire rd_clk,rd_rst,pop,output reg [17:0] data_out,output wire empty);
    (* ram_style="bram_9k" *) reg [17:0] memory[0:(1<<ABITS)-1];
    reg [ABITS:0] wr_binary,rd_binary,wr_gray,rd_gray;
    (* async_reg="true" *) reg [ABITS:0] rd_sync1,rd_sync2,wr_sync1,wr_sync2;
    assign full=wr_gray=={~rd_sync2[ABITS:ABITS-1],rd_sync2[ABITS-2:0]};
    assign empty=rd_gray==wr_sync2;
    wire [ABITS:0] next_wr=wr_binary+1'b1,next_rd=rd_binary+1'b1;
    always @(posedge wr_clk)if(push && !full && !wr_rst)memory[wr_binary[ABITS-1:0]]<=data_in;
    always @(posedge rd_clk)data_out<=memory[rd_binary[ABITS-1:0]];
    always @(posedge wr_clk or posedge wr_rst)begin
        if(wr_rst)begin wr_binary<=0;wr_gray<=0;rd_sync1<=0;rd_sync2<=0;end
        else begin
            rd_sync1<=rd_gray;rd_sync2<=rd_sync1;
            if(push && !full)begin wr_binary<=next_wr;wr_gray<=(next_wr>>1)^next_wr;end
        end
    end
    always @(posedge rd_clk or posedge rd_rst)begin
        if(rd_rst)begin rd_binary<=0;rd_gray<=0;wr_sync1<=0;wr_sync2<=0;end
        else begin
            wr_sync1<=wr_gray;wr_sync2<=wr_sync1;
            if(pop && !empty)begin rd_binary<=next_rd;rd_gray<=(next_rd>>1)^next_rd;end
        end
    end
endmodule

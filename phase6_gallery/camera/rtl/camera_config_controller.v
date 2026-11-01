// Configuration sequencer; transport is the separately verified SCCB master.
module camera_config_controller #(
    parameter integer CLK_HZ=50000000,
    parameter integer POWER_CYCLES=CLK_HZ/50,
    parameter integer RESET_CYCLES=CLK_HZ/200,
    parameter integer SETTLE_CYCLES=CLK_HZ/50,
    parameter integer MS_CYCLES=CLK_HZ/1000,
    parameter TEST_PATTERN=1,SIMPLE_AWB=0
)(
    input wire clk,rst,
    output reg cam_pwdn,cam_reset_n,
    output reg bus_start, output wire bus_read,
    output wire [15:0] bus_addr, output wire [7:0] bus_write,
    input wire bus_busy,bus_done,input wire [7:0] bus_data,input wire [2:0] bus_error,
    output reg complete,ready,output reg [2:0] error,
    output reg [15:0] chip_id,failed_addr,
    output reg [7:0] actual_data,expected_data,
    output reg [8:0] index
);
    reg [3:0] state;
    reg [31:0] count;
    wire [1:0] op;
    wire [7:0] mask;
    wire [8:0] delay_ms;
    camera_config_rom #(.TEST_PATTERN(TEST_PATTERN),.SIMPLE_AWB(SIMPLE_AWB)) rom(.index(index),.op(op),.addr(bus_addr),.data(bus_write),.mask(mask),.delay_ms(delay_ms));
    assign bus_read=op==1;
    always @(posedge clk) begin
        bus_start<=0;
        if(rst)begin
            state<=0;count<=0;cam_pwdn<=1;cam_reset_n<=0;bus_start<=0;
            complete<=0;ready<=0;error<=0;chip_id<=0;failed_addr<=0;
            actual_data<=0;expected_data<=0;index<=0;
        end else case(state)
            0: if(count==POWER_CYCLES-1)begin cam_pwdn<=0;count<=0;state<=1;end else count<=count+1'b1;
            1: if(count==RESET_CYCLES-1)begin cam_reset_n<=1;count<=0;state<=2;end else count<=count+1'b1;
            2: if(count==SETTLE_CYCLES-1)begin count<=0;state<=3;end else count<=count+1'b1;
            3: case(op)
                0,1:if(!bus_busy)begin bus_start<=1;state<=4;end
                2:begin count<=delay_ms*MS_CYCLES-1;state<=5;end
                3:begin complete<=1;ready<=1;state<=7;end
            endcase
            4: if(bus_done)begin
                if(bus_read && bus_addr==16'h300a)chip_id[15:8]<=bus_data;
                if(bus_read && bus_addr==16'h300b)chip_id[7:0]<=bus_data;
                if(bus_error!=0 || (bus_read && (bus_data & mask)!=(bus_write & mask)))begin
                    complete<=1;ready<=0;failed_addr<=bus_addr;actual_data<=bus_data;expected_data<=bus_write;
                    error<=bus_error!=0 ? bus_error : ((bus_addr==16'h300a || bus_addr==16'h300b) ? 3'd4 : 3'd5);
                    state<=7;
                end else begin index<=index+1'b1;state<=3;end
            end
            5:if(count==0)begin index<=index+1'b1;state<=3;end else count<=count-1'b1;
            default: ;
        endcase
    end
endmodule

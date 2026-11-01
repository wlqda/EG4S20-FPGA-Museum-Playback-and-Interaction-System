// Same pixel clock as the Gallery UI. Queue a gesture until a UI-safe vblank.
module camera_nav_adapter #(parameter WAIT_CYCLES=12500000)(input wire clk,rst,enabled,frame_start,ready,event_valid,
    input wire [2:0] direction,output reg [7:0] events,output reg overflow);
    reg pending;reg [2:0] queued;
    localparam AW=WAIT_CYCLES>1 ? $clog2(WAIT_CYCLES+1) : 1;
    reg [AW-1:0] age;
    always @(posedge clk)begin
        events<=0;
        if(rst)begin age<=0;pending<=0;queued<=0;events<=0;overflow<=0;end
        else if(!enabled)begin age<=0;pending<=0;overflow<=0;end
        else if(!overflow)begin
            if(pending && age<WAIT_CYCLES)age<=age+1'b1;
            if(pending && age>=WAIT_CYCLES-1)pending<=0;
            if(pending && age<WAIT_CYCLES-1 && frame_start && ready)begin
                case(queued)
                    2:events<=8'h02; // LEFT: previous
                    3:events<=8'h01; // RIGHT: next
                    4:events<=8'h08; // UP: back
                    5:events<=8'h04; // DOWN: enter
                    default:events<=0;
                endcase
                pending<=0;
            end
            if(event_valid && direction>=2 && direction<=5)begin
                if(pending && age<WAIT_CYCLES-1 && !(frame_start && ready))begin overflow<=1;pending<=0;events<=0;end
                else begin age<=0;pending<=1;queued<=direction;end
            end
        end
    end
endmodule

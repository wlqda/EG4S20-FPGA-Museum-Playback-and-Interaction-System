// 2M x 32 internal SDR SDRAM, 100 MHz, BL8, CAS3, auto precharge.
// Controller registers change on clk; SDRAM uses the dedicated phase clock.
module sdram_burst #(parameter INIT_CYCLES=20000, REFRESH_CYCLES=600,
 parameter CAPTURE_DELAY=4)(
 input clk,rst, input req,write_req, input [20:0] word_addr,
 input [31:0] write_data, output reg ready, output reg busy,
 output write_take,output accept, output reg read_valid, output reg [31:0] read_data,
 output reg done,
 output reg ras_n,cas_n,we_n, output reg [10:0] addr,
 output reg [1:0] ba, inout [31:0] dq
);
 localparam INIT=0,IPRE=1,IREF=2,IMODE=3,IDLE=4,ACT=5,COL=6,
 WDATA=7,RWAIT=8,RDATA=9,REC=10,REF=11;
 reg [3:0] state;
 reg [15:0] timer,refresh_timer;
 reg [3:0] init_refresh,count;
 reg [20:0] saved_addr;
 reg saved_write,drive;
 reg [31:0] dq_out;
 assign dq=drive ? dq_out : 32'bz;
 // First word is consumed with WRITE command; subsequent seven are sequential.
 assign write_take=(state==COL && saved_write) || state==WDATA;
 assign accept=state==IDLE && refresh_timer<REFRESH_CYCLES && req;
 // Capture the bus directly: read_valid selects meaningful samples downstream.
 // Avoid a feedback/reset mux on the timing-critical SDRAM input path.
 always @(posedge clk) read_data<=dq;
 always @(posedge clk) begin
  if(rst) begin
   state<=INIT;timer<=0;refresh_timer<=0;init_refresh<=0;count<=0;
   ready<=0;busy<=1;done<=0;read_valid<=0;
   ras_n<=1;cas_n<=1;we_n<=1;addr<=0;ba<=0;drive<=0;dq_out<=0;
   saved_addr<=0;saved_write<=0;
  end else begin
   ras_n<=1;cas_n<=1;we_n<=1;done<=0;read_valid<=0;
   if(ready && refresh_timer<REFRESH_CYCLES) refresh_timer<=refresh_timer+1'b1;
   case(state)
    INIT: if(timer==INIT_CYCLES-1) begin
     ras_n<=0;we_n<=0;addr<=11'h400;timer<=0;state<=IPRE;
    end else timer<=timer+1'b1;
    IPRE: if(timer==3) begin
     ras_n<=0;cas_n<=0;timer<=0;init_refresh<=1;state<=IREF;
    end else timer<=timer+1'b1;
    IREF: if(timer==9) begin
     timer<=0;
     if(init_refresh==8) begin
      ras_n<=0;cas_n<=0;we_n<=0;addr<=11'h033;ba<=0;state<=IMODE;
     end else begin ras_n<=0;cas_n<=0;init_refresh<=init_refresh+1'b1;end
    end else timer<=timer+1'b1;
    IMODE: if(timer==3) begin ready<=1;busy<=0;state<=IDLE;refresh_timer<=0;end
     else timer<=timer+1'b1;
    IDLE: begin
     drive<=0;
     if(refresh_timer>=REFRESH_CYCLES) begin
      ras_n<=0;cas_n<=0;state<=REF;timer<=0;busy<=1;refresh_timer<=0;
     end else if(req) begin
      saved_addr<=word_addr;saved_write<=write_req;busy<=1;
      ras_n<=0;addr<=word_addr[20:10];ba<=word_addr[9:8];timer<=0;state<=ACT;
     end
    end
    ACT: if(timer==1) state<=COL;else timer<=timer+1'b1;
    COL: begin
     cas_n<=0;we_n<=!saved_write;addr<={1'b1,2'b00,saved_addr[7:0]};
     count<=0;
     if(saved_write) begin drive<=1;dq_out<=write_data;count<=1;state<=WDATA;end
     else state<=RWAIT;
    end
    WDATA: begin
     dq_out<=write_data;
     if(count==7) begin timer<=0;state<=REC;end else count<=count+1'b1;
    end
    RWAIT: if(count==CAPTURE_DELAY) begin
     read_valid<=1;count<=1;state<=RDATA;
    end else count<=count+1'b1;
    RDATA: begin
     read_valid<=1;
     if(count==7) begin timer<=0;state<=REC;end else count<=count+1'b1;
    end
    REC: begin
     drive<=0;
     if(timer==5) begin done<=1;busy<=0;state<=IDLE;end else timer<=timer+1'b1;
    end
    REF: if(timer==9) begin busy<=0;state<=IDLE;end else timer<=timer+1'b1;
   endcase
  end
 end
endmodule

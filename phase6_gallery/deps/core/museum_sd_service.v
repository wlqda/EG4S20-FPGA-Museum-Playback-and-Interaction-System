// Two clients, one initialized SD host. All ports are in the memory domain.
// Ownership includes two trailing cycles so a late CRC commit cannot leak.
module museum_sd_service(
 input wire clk,rst,
 input wire a_req,b_req,
 input wire [31:0] a_lba,b_lba,
 input wire [22:0] a_count,b_count,
 input wire a_resume,b_resume,
 output wire a_ready,b_ready,
 output wire [7:0] a_data,b_data,
 output wire a_valid,b_valid,a_commit,b_commit,
 output wire a_done,b_done,
 output wire [7:0] a_error,b_error,
 output wire host_req,
 output reg [31:0] host_lba,
 output reg [22:0] host_count,
 output wire host_resume,
 input wire host_ready,
 input wire [7:0] host_data,host_error,
 input wire host_valid,host_commit,host_done
);
 localparam IDLE=0,ISSUE=1,ACTIVE=2,TAIL1=3,TAIL2=4,REJECT=5;
 reg [2:0] state;
 reg owner,last_owner;
 // last_owner=1 at reset gives A the first simultaneous request.
 wire choose_b=b_req && (!a_req || !last_owner);
 wire available=(state==IDLE) && host_ready;
 wire owned=state!=IDLE;
 wire transfer=state==ISSUE || state==ACTIVE;
 wire failure=transfer && host_error!=0;
 wire completion=(transfer && (host_done || failure)) || state==REJECT;
 assign a_ready=available && !choose_b;
 assign b_ready=available && choose_b;
 assign host_req=state==ISSUE;
 assign host_resume=owned && (owner ? b_resume : a_resume);
 assign a_data=host_data;
 assign b_data=host_data;
 assign a_valid=transfer && !owner && host_valid;
 assign b_valid=transfer && owner && host_valid;
 assign a_commit=owned && !owner && state!=REJECT && host_commit;
 assign b_commit=owned && owner && state!=REJECT && host_commit;
 assign a_done=completion && !owner;
 assign b_done=completion && owner;
 assign a_error=owned && !owner ? (state==REJECT ? 8'he2 : host_error) : 8'd0;
 assign b_error=owned && owner ? (state==REJECT ? 8'he2 : host_error) : 8'd0;
 always @(posedge clk) begin
  if(rst)begin state<=IDLE;owner<=0;last_owner<=1;host_lba<=0;host_count<=0;end
  else case(state)
   IDLE: if(available && (a_req || b_req))begin
    owner<=choose_b;last_owner<=choose_b;
    host_lba<=choose_b ? b_lba : a_lba;
    host_count<=choose_b ? b_count : a_count;
    state<=(choose_b ? b_count==0 : a_count==0) ? REJECT : ISSUE;
   end
   ISSUE: if(host_done || failure)state<=TAIL1;
          else if(host_ready)state<=ACTIVE;
   ACTIVE: if(host_done || failure)state<=TAIL1;
   REJECT: state<=TAIL1;
   TAIL1: state<=TAIL2;
   TAIL2: state<=IDLE;
   default: state<=IDLE;
  endcase
 end
endmodule

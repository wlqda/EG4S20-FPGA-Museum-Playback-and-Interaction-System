// Synchronous FIFO with a registered, continuously prefetched front word.
module word_fifo #(parameter AW=10)(input clk,rst,push,pop,
 input [31:0] data,output reg [31:0] q,output [AW:0] used);
 (* ram_style="bram_32k" *) reg [31:0] mem[0:(1<<AW)-1];
 reg [AW-1:0] wp,rp;
 reg [AW:0] count;
 wire [AW-1:0] read_addr=rp+pop;
 assign used=count;
 always @(posedge clk) begin
  if(push) mem[wp]<=data;
  q<=mem[read_addr];
  if(rst) begin wp<=0;rp<=0;count<=0;end
  else begin
   if(push) wp<=wp+1'b1;
   if(pop) rp<=rp+1'b1;
   case({push,pop}) 2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;endcase
  end
 end
endmodule

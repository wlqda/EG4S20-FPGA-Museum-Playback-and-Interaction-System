// Dual-clock PCM FIFO. Each entry includes the final-sample marker.
// Both domains must be held in reset during session changes. Read data is a
// synchronous RAM output; rvalid waits two cycles after empty before allowing use.
module museum_pcm_fifo #(parameter ADDR=12)(
 input wclk,wrst,input [16:0] wdata,input wvalid,output wready,
 input rclk,rrst,output reg [16:0] rdata,output rvalid,input rready);
 (* ram_style="block" *) reg [16:0] mem[0:(1<<ADDR)-1];
 reg [ADDR:0] wp,rp,wg,rg;
 (* async_reg="true" *) reg [ADDR:0] rg0,rg1,wg0,wg1;
 reg full,empty;reg [1:0] readable;
 wire push=wvalid && wready,pop=rvalid && rready;
 wire [ADDR:0] wn=wp+push,rn=rp+pop;
 wire [ADDR:0] wgn=(wn>>1)^wn,rgn=(rn>>1)^rn;
 assign wready=!full && !wrst;
 assign rvalid=readable[1] && !empty && !rrst;
 always @(posedge wclk)begin
  if(wrst)begin wp<=0;wg<=0;rg0<=0;rg1<=0;full<=0;end
  else begin
   rg0<=rg;rg1<=rg0;
   if(push)mem[wp[ADDR-1:0]]<=wdata;
   wp<=wn;wg<=wgn;
   full<=wgn=={~rg1[ADDR:ADDR-1],rg1[ADDR-2:0]};
  end
 end
 always @(posedge rclk)begin
  rdata<=mem[rp[ADDR-1:0]];
  if(rrst)begin rp<=0;rg<=0;wg0<=0;wg1<=0;empty<=1;readable<=0;end
  else begin
   wg0<=wg;wg1<=wg0;rp<=rn;rg<=rgn;empty<=rgn==wg1;
   // A pop changes the RAM address. Suppress next cycle's stale RAM output.
   if(empty || pop)readable<=0;else readable<={readable[0],1'b1};
  end
 end
endmodule

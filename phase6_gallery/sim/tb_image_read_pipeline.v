`timescale 1ns/1ps
module tb_image_read_pipeline;
 reg clk=0;always #5 clk=~clk;
 reg rst=1;reg [1:0] zoom=0,bank=0;reg toggle=0;reg [8:0] line=0;
 wire req,write_req,ack;wire [20:0] address;wire [31:0] word;
 wire [8:0] n0,n1;wire ready0,ready1;
 reg busy=0,accepted=0,done=0,valid=0;reg [31:0] data=0;
 integer state=0,index=0,bursts=0,mode,b,row,pixel,checks=0;
 reg [20:0] saved;reg [31:0] expected;reg passed=0;
 museum_gallery_image_memory dut(.clk(clk),.rst(rst),.pixel_clk(clk),.pixel_rst(rst),.zoom(zoom),
 .begin_valid(1'b0),.begin_ready(),.image_index(16'd0),.image_width(16'd640),.image_height(16'd480),
 .pixel_valid(1'b0),.pixel_ready(),.pixel_addr(19'd0),.pixel_rgb(24'd0),
 .end_valid(1'b0),.end_ready(),.abort(1'b0),.frame_toggle(),.frame_bank(),.display_ack(1'b0),
 .active_index(),.error(),.line_toggle(toggle),.line_number(line),.line_frame_bank(bank),
 .pixel_address(11'd0),.pixel_word(word),.line0_number(n0),.line1_number(n1),
 .line0_epoch(),.line1_epoch(),.line0_ready(ready0),.line1_ready(ready1),.line_ack(ack),
 .req(req),.write_req(write_req),.word_addr(address),.write_data(),.memory_ready(1'b1),
 .controller_busy(busy),.controller_done(done),.read_valid(valid),.write_take(1'b0),
 .request_accepted(accepted),.read_data(data));
 function integer source_row;input integer z,r;begin
  source_row=z==2 ? 180+r/4 : z==1 ? 120+r/2 : r;
 end endfunction
 always @(posedge clk)begin
  accepted<=0;done<=0;valid<=0;
  if(rst)begin state<=0;busy<=0;end
  else case(state)
   0:if(req && !busy)begin
    expected=32'h100000+b*32'h80000+source_row(mode,row)*640+bursts*8;
    if(write_req || address!==expected[20:0])$fatal(1,"read address z=%0d bank=%0d row=%0d burst=%0d got=%h expected=%h",mode,b,row,bursts,address,expected);
    bursts=bursts+1;saved<=address;accepted<=1;busy<=1;index<=0;state<=1;
   end
   1:begin valid<=1;data<=saved+index;
    if(index==7)state<=2;else index<=index+1;
   end
   2:begin done<=1;busy<=0;state<=3;end
   3:state<=0;
  endcase
 end
 initial begin
  repeat(3)@(negedge clk);rst=0;
  for(mode=0;mode<3;mode=mode+1)for(b=0;b<2;b=b+1)begin
   zoom=mode;bank=b;repeat(6)@(negedge clk);
   for(row=0;row<480;row=row+1)begin
    @(negedge clk);line=row;bursts=0;toggle=~toggle;
    wait(ack==toggle);@(negedge clk);
    if(bursts!=80 || (row%2 ? (!ready1 || n1!=row) : (!ready0 || n0!=row)))$fatal(1,"line not complete");
    for(pixel=0;pixel<640;pixel=pixel+1)begin
     expected=32'h100000+b*32'h80000+source_row(mode,row)*640+pixel;
     if(dut.lines[(row%2)*1024+pixel]!==expected)$fatal(1,"line buffer pixel mismatch");
     checks=checks+1;
    end
   end
  end
  passed=1;$display("PASS image read pipeline: 2880 complete lines, 230400 bursts, %0d pixels, both banks and all zooms",checks);$finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule

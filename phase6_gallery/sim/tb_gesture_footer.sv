`timescale 1ns/1ps
module tb_gesture_footer;
reg clk=0;always #5 clk=~clk;reg rst=0,gesture_enabled=0,editing=0;reg[9:0] x=0,y=470;reg[3:0] page=7;wire[23:0] rgb;reg passed=0;integer ink=0,i,j;
museum_phase6_render dut(.clk(clk),.rst(rst),.x(x),.y(y),.active(1'b1),.base_rgb(24'h432187),.page(page),.focus(2'd0),.editing(editing),.autoplay(1'b1),.gesture_enabled(gesture_enabled),.interval_seconds(6'd5),.photo_index(4'd0),.zoom(2'd0),.fade_level(5'd16),.volume(9'd256),.brightness(9'd256),.image_mode(1'b1),.playing(1'b0),.paused(1'b0),.screen_visible(1'b1),.frame_valid(1'b1),.media_error(8'd0),.out_rgb(rgb));
task settle;begin repeat(3)@(negedge clk);end endtask
initial begin
settle;if(rgb!=24'h432187)$fatal(1,"key mode changed");
gesture_enabled=1;settle;if(rgb!=24'hf4eee4)$fatal(1,"old key hint not covered");
for(i=0;i<8;i=i+1)begin page=i;settle;if(dut.footer_text==0 && i!=3 && i!=6)$fatal(1,"missing page hint");end
page=3;x=240;settle;if(dut.footer_text[127:112]!=16'h4e0b)$fatal(1,"video hint");
page=7;x=32;settle;if(dut.footer_text[127:112]!=16'h5de6)$fatal(1,"carousel hint");
for(j=436;j<452;j=j+1)for(i=32;i<544;i=i+1)begin x=i;y=j;settle;if(rgb==24'h534b40)ink=ink+1;end
if(ink<100)$fatal(1,"hint font invisible");
page=5;editing=1;ink=0;
for(j=436;j<452;j=j+1)for(i=32;i<576;i=i+1)begin x=i;y=j;settle;if(rgb==24'h534b40)ink=ink+1;end
if(ink<100)$fatal(1,"editing mode hid footer text");
x=0;y=470;gesture_enabled=0;settle;if(rgb!=24'h432187)$fatal(1,"key mode not restored");
passed=1;$display("PASS gesture footer: all pages, video/carousel actions, visible text, mode switch restores original asset");$finish;
end
endmodule

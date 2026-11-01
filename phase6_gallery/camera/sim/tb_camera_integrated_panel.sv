`timescale 1ns/1ps
module tb_camera_integrated_panel;
reg clk=0;always #5 clk=~clk;reg rst=1,de=1;reg[9:0] x=799,y=524;reg[23:0] base_rgb=24'h432187;
reg calibration=0,background_ready=1,fault=0;reg[2:0] stage=2,error=0,pose=0;reg collecting=0,armed=1;reg[31:0] event_sequence=0;
reg mask_valid=0;reg[6:0] mask_x=0;reg[5:0] mask_y=0;reg skin=0,preview_de=0,preview_clear=0;reg[9:0] preview_x=0,preview_y=0;reg[23:0] preview_rgb=0;
reg preparing=0,source_fault=0,nav_overflow=0;reg nav_ready=1,target_visible=0;reg[9:0] target_x=320,target_y=240;reg preview_enable=1,diagnostics=0,recognition_enabled=1;
wire[23:0] rgb;wire[23:0] footer_rgb;reg[23:0] home[0:307199];reg[23:0] exported;reg passed=0;
museum_phase6_render footer(.clk(clk),.rst(rst),.x(x),.y(y),.active(de),.base_rgb(base_rgb),.page(4'd0),.focus(2'd2),.editing(1'b0),.autoplay(1'b1),.gesture_enabled(1'b1),.interval_seconds(6'd5),.photo_index(4'd0),.zoom(2'd0),.fade_level(5'd16),.volume(9'd256),.brightness(9'd256),.image_mode(1'b1),.playing(1'b0),.paused(1'b0),.screen_visible(1'b1),.frame_valid(1'b1),.media_error(8'd0),.out_rgb(footer_rgb));integer i,j,ink=0,f;
camera_pose_overlay #(.SWIPE_MODE(1),.MIRROR_X(1),.INTEGRATED_STYLE(1),.ROI_Y0(16),.ROI_Y1(464)) dut(.*);
function[23:0] pattern(input integer xx,yy);begin pattern={8'(xx*3),8'(yy*4),8'((xx+yy)*2)};end endfunction
function[23:0] quant(input[23:0] c);begin quant={{c[23:21],c[23:21],c[23:22]},{c[15:13],c[15:13],c[15:14]},{c[7:6],c[7:6],c[7:6],c[7:6]}};end endfunction
task sample(input integer xx,yy);begin @(negedge clk);x=xx==0 ? 799 : xx-1;y=xx==0 ? yy-1 : yy;@(posedge clk);#1;x=xx;y=yy;#1;end endtask
initial begin
repeat(4)@(negedge clk);rst=0;
for(j=0;j<60;j=j+1)for(i=0;i<80;i=i+1)begin
 preview_de=1;preview_x=i*8;preview_y=j*8;preview_rgb=pattern(i,j);mask_valid=1;mask_x=i;mask_y=j;skin=1;@(negedge clk);
end
preview_x=639;preview_y=479;mask_valid=0;@(negedge clk);preview_de=0;
sample(200,0);if(rgb!=base_rgb)$fatal(1,"legacy top text remains");
sample(500,160);if(rgb!=base_rgb)$fatal(1,"panel overlaps home card");
sample(500,60);if(rgb!=base_rgb)$fatal(1,"outside preview changed");
sample(503,60);if(rgb!=24'h8c8a7e)$fatal(1,"preview border");
sample(520,80);if(rgb!=quant(pattern(63,38)))$fatal(1,"preview mapping %h",rgb);
for(j=124;j<140;j=j+1)for(i=504;i<632;i=i+1)begin sample(i,j);if(rgb==24'h243938)ink=ink+1;end
if(ink<40)$fatal(1,"Chinese status absent");
recognition_enabled=0;sample(520,80);if(dut.panel_message!=0)$fatal(1,"off message");recognition_enabled=1;
background_ready=0;preview_clear=1;repeat(2)@(negedge clk);preview_clear=0;sample(520,80);if(dut.panel_message!=3)$fatal(1,"background message");
background_ready=1;fault=1;sample(520,80);if(dut.panel_message!=1)$fatal(1,"fault message");fault=0;armed=0;stage=0;sample(520,80);if(dut.panel_message!=13)$fatal(1,"no frame message");
preparing=1;sample(520,80);if(dut.panel_message!=2)$fatal(1,"preparation priority");
source_fault=1;sample(520,80);if(dut.panel_message!=1)$fatal(1,"source fault priority");source_fault=0;preparing=0;
nav_overflow=1;sample(520,80);if(dut.panel_message!=12)$fatal(1,"overflow distinction");nav_overflow=0;
stage=4;error=2;sample(520,80);if(dut.panel_message!=11)$fatal(1,"edge rejection prompt");
stage=1;sample(520,80);if(dut.panel_message!=10)$fatal(1,"confirm prompt");
stage=3;armed=1;sample(520,80);if(dut.panel_message!=6)$fatal(1,"tracking overrides armed");
diagnostics=1;sample(520,80);if(dut.panel_message!=9)$fatal(1,"diagnostic prompt");diagnostics=0;stage=2;
preview_enable=0;sample(520,60);if(rgb!=base_rgb)$fatal(1,"hidden surround");sample(520,130);if(rgb!=base_rgb)$fatal(1,"hidden text");preview_enable=1;
// Export actual RTL pixels over the real home asset for visual inspection.
background_ready=1;armed=1;preview_de=1;preview_x=639;preview_y=479;repeat(2)@(negedge clk);preview_de=0;
f=$fopen("home_preview.hex","r");
if(f)begin $fclose(f);$readmemh("home_preview.hex",home);end
else for(i=0;i<307200;i=i+1)home[i]=base_rgb;
f=$fopen("panel.ppm","w");$fdisplay(f,"P3\n640 480\n255");
for(j=0;j<480;j=j+1)for(i=0;i<640;i=i+1)begin base_rgb=home[j*640+i];sample(i,j);exported=rgb;
if(j>=420)begin
 // Renderer has two sequential stages; export output, not its pre-font color.
 x=i;y=j;repeat(3)@(posedge clk);#1;exported=footer_rgb;
end
$fdisplay(f,"%d %d %d",exported[23:16],exported[15:8],exported[7:0]);end
$fclose(f);passed=1;$display("PASS integrated panel: title, ROI surround, mirror mapping, no card overlap, states and SW2 hide");$finish;
end
initial begin #20000000;$fatal(1,"watchdog");end
endmodule

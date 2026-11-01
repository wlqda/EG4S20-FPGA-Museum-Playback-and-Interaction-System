// 640x480 HDMI at 25 MHz; 640x360 video centered with 60 black lines each side.
module museum_phase1_display #(parameter SHOW_STATUS=1)(input clk,rst,input frame_toggle,input [1:0] frame_bank,
 output reg display_ack,output reg [1:0] display_bank,
 output reg line_toggle,output reg [8:0] line_number,
 input line_ack,input [8:0] line0_number,line1_number,
 input line0_epoch,line1_epoch,line0_ready,line1_ready,
 output [9:0] pixel_address,input [31:0] pixel_word,
 input [7:0] error_async,input mounted_async,
 input [3:0] sd_stage_async,input [7:0] fs_stage_async,
 input audio_due_toggle,input [1:0] audio_due_bank,input [7:0] audio_underflows,
 output [7:0] display_error,output [9:0] x,y, output video_started,output reg hs,vs,de,output [23:0] rgb);
 reg [9:0] h,v;
 reg [1:0] ft_pipe,la_pipe,l0r_pipe,l1r_pipe,l0e_pipe,l1e_pipe;
 reg [1:0] bank_pipe0,bank_pipe1;
 reg [8:0] l0n_pipe0,l0n_pipe1,l1n_pipe0,l1n_pipe1;
 reg [7:0] error0,error1,fs0,fs1;
 reg [3:0] sd0,sd1;
 reg [9:0] overlay_x,overlay_y;
 assign display_error=error1;assign x=overlay_x;assign y=overlay_y;
 wire overlay_ink;
 error_overlay #(.VERSION_DIGIT("8")) diagnostic(.x(overlay_x),.y(overlay_y),.code(error1),
  .sd_stage(sd1),.fs_stage(fs1),.ink(overlay_ink));
 reg [1:0] mounted_pipe;
 reg have_frame,odd,video_active,good_line;
 reg last_due;
 assign video_started=have_frame;
 reg [24:0] second_cycles;
 reg [5:0] fps_count,fps;
 reg [7:0] missed_lines;
 wire status_ink;
 av_status_overlay status(.x(overlay_x),.y(overlay_y),.fps(fps),.missed_lines(missed_lines),.audio_underflows(audio_underflows),.ink(status_ink));
 wire [8:0] video_line=v-60;
 wire parity=video_line[0];
 wire line_ok=parity ? (l1r_pipe[1] && l1e_pipe[1]==display_ack && l1n_pipe1==video_line)
  : (l0r_pipe[1] && l0e_pipe[1]==display_ack && l0n_pipe1==video_line);
 assign pixel_address={parity,h[9:1]};
 wire [15:0] pixel=odd ? pixel_word[31:16] : pixel_word[15:0];
 wire [23:0] expanded={pixel[15:11],pixel[15:13],pixel[10:5],pixel[10:9],pixel[4:0],pixel[4:2]};
 assign rgb=error1!=0 ? (overlay_ink ? 24'hffffff : 24'hd02020) : !have_frame ?
  (mounted_pipe[1] ? 24'h2030c0 : 24'h606060) :
  video_active ? (good_line ? expanded : 24'hd020d0) :
  (SHOW_STATUS && status_ink ? 24'hb0b0b0 : 24'h000000);
 task request_line;
  input [8:0] number;
  begin line_number<=number;line_toggle<=~line_toggle;end
 endtask
 always @(posedge clk) begin
  if(rst) begin
   h<=0;v<=0;display_ack<=0;display_bank<=0;have_frame<=0;
   line_toggle<=0;line_number<=0;last_due<=0;hs<=1;vs<=1;de<=0;
   odd<=0;video_active<=0;good_line<=0;ft_pipe<=0;la_pipe<=0;
   l0r_pipe<=0;l1r_pipe<=0;l0e_pipe<=0;l1e_pipe<=0;
   bank_pipe0<=0;bank_pipe1<=0;second_cycles<=0;fps_count<=0;fps<=0;missed_lines<=0;
   l0n_pipe0<=0;l0n_pipe1<=0;l1n_pipe0<=0;l1n_pipe1<=0;
   overlay_x<=0;overlay_y<=0;fs0<=0;fs1<=0;sd0<=0;sd1<=0;error0<=0;error1<=0;mounted_pipe<=0;
  end else begin
   ft_pipe<={ft_pipe[0],frame_toggle};la_pipe<={la_pipe[0],line_ack};
   bank_pipe0<=frame_bank;bank_pipe1<=bank_pipe0;
   if(second_cycles==24999999) begin
    second_cycles<=0;fps<=fps_count;fps_count<=0;
   end else second_cycles<=second_cycles+1'b1;
   if(h==0 && v>=60 && v<420 && have_frame && !line_ok && missed_lines!=255)
    missed_lines<=missed_lines+1'b1;
   l0r_pipe<={l0r_pipe[0],line0_ready};l1r_pipe<={l1r_pipe[0],line1_ready};
   l0e_pipe<={l0e_pipe[0],line0_epoch};l1e_pipe<={l1e_pipe[0],line1_epoch};
   l0n_pipe0<=line0_number;l0n_pipe1<=l0n_pipe0;
   l1n_pipe0<=line1_number;l1n_pipe1<=l1n_pipe0;
   overlay_x<=h;overlay_y<=v;fs0<=fs_stage_async;fs1<=fs0;sd0<=sd_stage_async;sd1<=sd0;
   error0<=error_async;error1<=error0;mounted_pipe<={mounted_pipe[0],mounted_async};
   if(h==799) begin h<=0;if(v==524)v<=0;else v<=v+1'b1;end else h<=h+1'b1;
   hs<=!(h>=656 && h<752);vs<=!(v>=490 && v<492);de<=h<640 && v<480;
   odd<=h[0];video_active<=h<640 && v>=60 && v<420;good_line<=line_ok;
   if(h==0 && v==480) begin
    if(ft_pipe[1]!=display_ack && (!have_frame ||
       (audio_due_toggle!=last_due && audio_due_bank==bank_pipe1))) begin
     display_ack<=ft_pipe[1];display_bank<=bank_pipe1;have_frame<=1;
     last_due<=audio_due_toggle;
     if(second_cycles==24999999) fps<=fps_count+1'b1;
     else fps_count<=fps_count+1'b1;
    end
    if((have_frame || ft_pipe[1]!=display_ack) && la_pipe[1]==line_toggle) request_line(0);
   end
   if(h==0 && v==481 && have_frame && la_pipe[1]==line_toggle) request_line(1);
   if(h==0 && v>=60 && v<419 && have_frame && la_pipe[1]==line_toggle)
    request_line(video_line+1'b1);
  end
 end
endmodule

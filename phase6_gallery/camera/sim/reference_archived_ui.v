// Pixel-domain UI. Sixteen original screens plus thirteen photo slides; commands remain
// stable under backpressure. Only one screen request is outstanding at a time.
module museum_phase6_ui #(
 parameter GESTURE_MODE=0, CLK_HZ=25000000, IDLE_SECONDS=20, ZOOM_IDLE_SECONDS=5
)(input clk,rst,frame_start,input [7:0] events,
 input image_mode,media_playing,media_paused,media_busy,
 input [15:0] resource_count,shown_index,input shown_valid,
 input [7:0] media_error,
 input [8:0] volume,brightness,
 output reg [3:0] page,output reg [1:0] focus,exhibit,
 output reg editing,output reg autoplay,output reg [5:0] interval_seconds,
 output wire welcome,output reg [4:0] screen_index,
 output reg [3:0] photo_index,output reg [1:0] zoom,
 output reg [4:0] fade_level,
 output reg cmd_valid,input cmd_ready,output reg [7:0] cmd_opcode,
 output reg [31:0] cmd_arg,output wire nav_ready);
 localparam HOME=0,LIST=1,DETAIL=2,VIDEO=3,AUDIO=4,SETTINGS=5,WELCOME=7;
 reg [3:0] page_n;reg [1:0] focus_n,exhibit_n;reg edit_n;
 reg [31:0] second_tick;reg [7:0] idle_seconds;reg [5:0] slide_seconds;
 reg [3:0] next_photo;reg [1:0] fade_state,zoom_n;
 reg [7:0] zoom_idle_seconds;
 reg idle_return,slide_due;
 reg last_screen_valid;reg [4:0] last_screen;
 reg av_wanted,pause_wanted,audio_from_detail;
 reg setting_pending;reg [7:0] setting_opcode;reg [31:0] setting_arg;
 wire ui_busy=cmd_valid || setting_pending;
 assign welcome=page==WELCOME;
 function [3:0] next_index;input [3:0] current;input backwards;begin
  next_index=backwards ? (current==0 ? 4'd12 : current-1'b1) :
                          (current==12 ? 4'd0 : current+1'b1);
 end endfunction
 function [1:0] owner;input [3:0] photo;begin
  owner=photo<3 ? 0 : photo<6 ? 1 : photo<10 ? 2 : 3;
 end endfunction
 always @* begin
  case(page)
   WELCOME:screen_index=5'd16+{1'b0,photo_index};
   HOME:screen_index=4;
   LIST:screen_index=5;
   DETAIL:screen_index=6+{2'b00,exhibit};
   AUDIO:screen_index=10+{2'b00,exhibit};
   SETTINGS:screen_index=14;
   default:screen_index=15;
  endcase
 end
 wire screen_ready=image_mode && shown_valid && shown_index=={11'd0,screen_index} && !media_busy;
 assign nav_ready=fade_state==0 && !ui_busy && (!GESTURE_MODE || (page==VIDEO || screen_ready));
 always @(posedge clk)begin
  if(rst)begin
   page<=GESTURE_MODE ? HOME : WELCOME;page_n<=GESTURE_MODE ? HOME : WELCOME;focus<=0;focus_n<=0;exhibit<=0;exhibit_n<=0;
   editing<=0;edit_n<=0;autoplay<=!GESTURE_MODE;interval_seconds<=8;
   photo_index<=0;next_photo<=0;zoom<=0;zoom_n<=0;fade_level<=16;fade_state<=0;zoom_idle_seconds<=0;
   second_tick<=0;idle_seconds<=0;slide_seconds<=0;idle_return<=0;slide_due<=0;
   last_screen_valid<=0;last_screen<=0;av_wanted<=0;pause_wanted<=0;audio_from_detail<=0;
   setting_pending<=0;setting_opcode<=0;setting_arg<=0;
   cmd_valid<=0;cmd_opcode<=0;cmd_arg<=0;
  end else begin
   // All public page and focus changes commit at vertical blanking.
   if(frame_start)begin page<=page_n;focus<=focus_n;exhibit<=exhibit_n;editing<=edit_n;zoom<=zoom_n;end
   if(events!=0)begin second_tick<=0;idle_seconds<=0;slide_seconds<=0;zoom_idle_seconds<=0;idle_return<=0;slide_due<=0;end
   else if(second_tick==CLK_HZ-1)begin
    second_tick<=0;
    if(!GESTURE_MODE && page!=WELCOME)begin
     if(idle_seconds==IDLE_SECONDS-1)begin idle_return<=1;idle_seconds<=0;end
     else idle_seconds<=idle_seconds+1'b1;
    end
    if(page==WELCOME && zoom!=0)begin
     if(zoom_idle_seconds==ZOOM_IDLE_SECONDS-1)begin zoom_n<=0;zoom_idle_seconds<=0;slide_seconds<=0;end
     else zoom_idle_seconds<=zoom_idle_seconds+1'b1;
    end
    if(page==WELCOME && zoom==0 && fade_state==0 && autoplay && screen_ready && media_error==0)begin
     if(slide_seconds+1>=interval_seconds)begin slide_due<=1;slide_seconds<=0;end
     else slide_seconds<=slide_seconds+1'b1;
    end else slide_seconds<=0;
   end else second_tick<=second_tick+1'b1;
   if(frame_start && events==0 && idle_return)begin
    page_n<=WELCOME;focus_n<=0;exhibit_n<=0;edit_n<=0;av_wanted<=0;idle_return<=0;
    photo_index<=0;next_photo<=0;zoom_n<=0;fade_state<=0;fade_level<=16;
   end else if(frame_start && events==0 && slide_due && fade_state==0 && zoom==0)begin
    next_photo<=next_index(photo_index,1'b0);fade_state<=1;slide_due<=0;
   end
   if(frame_start && page==WELCOME)begin
    case(fade_state)
     1:if(fade_level!=0)fade_level<=fade_level-1'b1;
       else begin photo_index<=next_photo;exhibit_n<=owner(next_photo);fade_state<=2;end
     2:if(screen_ready)fade_state<=3;
     3:if(fade_level!=16)fade_level<=fade_level+1'b1;
       else fade_state<=0;
    endcase
   end
   if(events[3])begin
    edit_n<=0;
    if(page_n==SETTINGS && edit_n)begin end
    else if(GESTURE_MODE && page_n==AUDIO)begin page_n<=audio_from_detail ? DETAIL : HOME;end
    else if(page_n==DETAIL || page_n==AUDIO)begin page_n<=LIST;focus_n<=exhibit_n;end
    else begin page_n<=HOME;focus_n<=0;zoom_n<=0;fade_state<=0;fade_level<=16;end
    av_wanted<=0;
   end else if(events[0] || events[1])begin
    case(page_n)
     HOME,LIST:focus_n<=events[0] ? focus_n+1'b1 : focus_n-1'b1;
     DETAIL,AUDIO:exhibit_n<=events[0] ? exhibit_n+1'b1 : exhibit_n-1'b1;
     WELCOME:if(zoom!=0)begin
       if(events[0] && zoom_n<2)zoom_n<=zoom_n+1'b1;
       else if(events[1] && zoom_n>1)zoom_n<=zoom_n-1'b1;
      end else if(fade_state==0)begin
       next_photo<=next_index(photo_index,events[1]);fade_state<=1;
      end
     SETTINGS:if(!edit_n)focus_n<=events[0] ? focus_n+1'b1 : focus_n-1'b1;
      else if(!ui_busy)begin
       case(focus_n)
        0:begin setting_opcode<=6;setting_arg<=events[0] ? (volume>=240 ? 256 : volume+16) : (volume<=16 ? 0 : volume-16);setting_pending<=1;end
        1:begin setting_opcode<=7;setting_arg<=events[0] ? (brightness>=240 ? 256 : brightness+16) : (brightness<=32 ? 16 : brightness-16);setting_pending<=1;end
        2:interval_seconds<=events[0] ? (interval_seconds>=60 ? 60 : interval_seconds+1'b1) : (interval_seconds<=5 ? 5 : interval_seconds-1'b1);
        3:autoplay<=~autoplay;
       endcase
      end
     default:;
    endcase
   end else if(events[2])begin
    case(page_n)
     WELCOME:begin if(GESTURE_MODE)begin page_n<=LIST;focus_n<=exhibit_n;zoom_n<=0;fade_state<=0;fade_level<=16;end else if(zoom_n==0)zoom_n<=1;else begin zoom_n<=0;slide_seconds<=0;end end
     HOME:begin
      case(focus_n)
       0:begin page_n<=LIST;focus_n<=exhibit_n;end
       1:begin page_n<=VIDEO;av_wanted<=0;pause_wanted<=0;end
       2:begin page_n<=AUDIO;audio_from_detail<=0;focus_n<=0;end
       3:begin page_n<=SETTINGS;focus_n<=0;end
      endcase
     end
     LIST:begin exhibit_n<=focus_n;page_n<=DETAIL;end
     DETAIL:begin page_n<=AUDIO;audio_from_detail<=1;end
     VIDEO:if(!av_wanted)begin av_wanted<=1;pause_wanted<=0;end else pause_wanted<=~pause_wanted;
     SETTINGS:edit_n<=~edit_n;
     default:;
    endcase
   end
   // Handshake updates only the command that actually left the register.
   if(cmd_valid && cmd_ready)begin
    cmd_valid<=0;
    if(cmd_opcode==1)begin last_screen<=cmd_arg[4:0];last_screen_valid<=1;end
   end
   if(!cmd_valid)begin
    if(setting_pending)begin cmd_valid<=1;cmd_opcode<=setting_opcode;cmd_arg<=setting_arg;setting_pending<=0;end
    else if(page==VIDEO && av_wanted)begin
     if(image_mode || !media_playing)begin cmd_valid<=1;cmd_opcode<=2;cmd_arg<=0;last_screen_valid<=0;end
     else if(media_paused!=pause_wanted)begin cmd_valid<=1;cmd_opcode<=4;cmd_arg<={31'd0,pause_wanted};end
    end else if(!last_screen_valid || last_screen!=screen_index || !image_mode)begin
     cmd_valid<=1;cmd_opcode<=1;cmd_arg<={27'd0,screen_index};
    end
   end
  end
 end
endmodule

module museum_phase6_core #(parameter EXTERNAL_GESTURE=0)(input sys_clk,sys_rst_n,input KEY2_N,KEY3_N,KEY4_N,input SW4,
 output SD_CLK,inout SD_CMD,input [3:0] SD_DAT,
 output HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,HDMI_DDC_SCL,inout HDMI_DDC_SDA,
 input [7:0] gesture_events,input [23:0] gesture_overlay_rgb,input gesture_keys_blocked,input clock_enabled,gesture_enabled,
 output gesture_pixel_clk,gesture_pixel_rst,gesture_de,gesture_frame_start,gesture_ready,
 output [9:0] gesture_x,gesture_y,output [23:0] gesture_base_rgb,output [3:0] gesture_page);
 // Declarations precede use for strict Verilog simulators; net equations are unchanged.
 wire pixel_clk;
 wire pixel_rst;
 // SW4 -> SWKEY_4 -> FPGA C5, 6_EX_DEVICE / 2_FPGA schematics.
 wire carousel_enabled;
 museum_slide_switch switch_filter(.clk(pixel_clk),.rst(pixel_rst),.switch_in(SW4),.enabled(carousel_enabled));
 wire playing;
 wire paused;

 wire serial_clk;
 wire mem_clk;
 wire pll_locked;
 wire pixel_raw;
 wire mem_raw;
 wire sdram_clk;
 wire sdram_raw;
 reg [15:0] power_delay=0;
 wire reset_source;
 reg [1:0] mr,pr;
 wire global_rst;

 wire rst;
 reg image_mode=1;
 reg [1:0] mode_sync;
 reg mode_last=1;
 reg [15:0] switch_reset=0;
 wire image_mode_m;
 wire image_rst;
 reg [1:0] image_reset_p;
 wire av_pixel_rst;
 wire image_pixel_rst;
 reg host_reset_q;
 wire ready;
 wire sd_valid;
 wire sd_done;
 wire sd_block_valid;
 wire fs_req;
 wire ext_req;
 wire mounted;
 wire prepared;
 wire resume_ok;
 wire [7:0] sd_data;
 wire [7:0] sd_error;
 wire [7:0] fs_error;
 wire [7:0] ext_error;
 wire [7:0] memory_error;
 wire [31:0] fs_lba;
 wire [31:0] ext_lba;
 wire [31:0] fat_lba;
 wire [31:0] data_lba;
 wire [31:0] first_cluster;
 wire [31:0] max_cluster;
 wire [31:0] file_size;
 wire [22:0] ext_count;
 wire [3:0] sd_debug;
 wire [4:0] fs_debug;
 wire [7:0] spc;
 wire [2:0] cluster_shift;
 reg [7:0] mount_sd_error;
 wire stream_valid;
 wire [7:0] stream_data;
 wire video_resume;
 wire video_valid;
 wire video_commit;
 wire audio_valid;
 wire audio_seal;
 wire audio_resume;
 wire [7:0] video_data;
 wire [7:0] audio_data;
 wire [7:0] demux_error;
 wire [7:0] audio_error;
 wire [1:0] packet_bank;
 wire [1:0] seal_bank;
 wire [1:0] audio_due_bank;
 wire audio_due_toggle;
 wire video_started;
 wire audio_sample_valid;
 wire [23:0] audio_left;
 wire [23:0] audio_right;
 wire [7:0] audio_underflows;
 wire av_error;
 wire frame_toggle;
 wire display_ack;
 wire line_toggle;
 wire line_ack;
 wire [1:0] frame_bank;
 wire [1:0] display_bank;
 wire [8:0] line_number;
 wire [8:0] line0_number;
 wire [8:0] line1_number;
 wire line0_epoch;
 wire line1_epoch;
 wire line0_ready;
 wire line1_ready;
 wire [9:0] pixel_address;
 wire [31:0] pixel_word;
 wire ras_n;
 wire cas_n;
 wire we_n;
 wire memory_ready;
 wire [10:0] addr;
 wire [1:0] ba;
 wire [31:0] dq;
 wire av_req;
 wire av_write;
 wire img_req;
 wire img_write;
 wire controller_busy;
 wire controller_done;
 wire controller_read_valid;
 wire controller_write_take;
 wire controller_accept;
 wire [20:0] av_addr;
 wire [20:0] img_addr;
 wire [31:0] av_data;
 wire [31:0] img_data;
 wire [31:0] controller_data;
 reg bus_owner;
 reg bus_pending,bus_client,bus_write_q;
 reg [20:0] bus_addr_q;
 wire [31:0] image_host_lba;
 wire [22:0] image_host_count;
 wire image_host_req;
 wire image_host_resume;
 wire narration_req;
 wire narration_ready;
 wire narration_resume;
 wire narration_valid;
 wire narration_commit;
 wire narration_done;
 wire [31:0] narration_lba;
 wire [22:0] narration_count;
 wire [7:0] narration_bytes;
 wire [7:0] narration_sd_error;
 wire narration_cmd_ready;
 wire narration_playing;
 wire narration_busy;
 wire narration_ended;
 wire narration_sample_valid;
 wire [7:0] narration_error;
 wire [23:0] narration_sample;
 wire resource_req;
 wire resource_ready;
 wire resource_resume;
 wire resource_valid;
 wire resource_commit;
 wire resource_done;
 wire [31:0] resource_lba;
 wire [22:0] resource_sectors;
 wire [7:0] resource_data;
 wire [7:0] resource_sd_error;
 reg scan_started,scan_start,auto_loaded;
 wire scan_done;
 wire resource_busy;
 wire select_ready;
 wire select_valid;
 wire [15:0] resource_count;
 wire [15:0] image_index;
 wire [15:0] image_width;
 wire [15:0] image_height;
 wire [15:0] image_active_index;
 wire [7:0] resource_error;
 wire [7:0] image_memory_error;
 wire image_begin;
 wire image_begin_ready;
 wire image_pixel_valid;
 wire image_pixel_ready;
 wire image_end;
 wire image_end_ready;
 wire image_abort;
 wire [18:0] image_pixel_addr;
 wire [23:0] image_pixel_rgb;
 reg select_toggle=0;
 reg [15:0] requested_index=0;
 reg [1:0] select_pipe,select_ack_pipe;
 reg select_ack,select_pending;
 reg [15:0] selected_index;
 wire cmd_ready;
 wire img_frame_toggle;
 wire img_display_ack;
 wire img_line_toggle;
 wire img_line_ack;
 wire [1:0] gallery_zoom;
 wire [1:0] img_frame_bank;
 wire [1:0] img_display_bank;
 wire [8:0] img_line_number;
 wire [8:0] img_line0_number;
 wire [8:0] img_line1_number;
 wire img_line0_epoch;
 wire img_line1_epoch;
 wire img_line0_ready;
 wire img_line1_ready;
 wire [10:0] img_pixel_address;
 wire [31:0] img_pixel_word;
 wire img_started;
 wire img_hs;
 wire img_vs;
 wire img_de;
 wire [9:0] img_x;
 wire [9:0] img_y;
 wire [23:0] img_rgb;
 wire de;
 wire vs;
 wire [9:0] gui_x;
 wire [9:0] gui_y;
 reg [15:0] count_meta,count_p,index_meta,index_p;
 reg busy_meta,busy_p;
 reg [7:0] image_error_meta,image_error_p;
 wire [7:0] av_display_error;
 wire av_hs;
 wire av_vs;
 wire av_de;
 wire [9:0] av_x;
 wire [9:0] av_y;
 wire [23:0] av_rgb;
 wire [7:0] error;
 reg [7:0] first_error,first_fs_stage;
 reg [3:0] first_sd_stage;
 wire [7:0] key_events;
 wire [7:0] cmd_opcode;
 wire [7:0] command_error;
 wire cmd_valid;
 wire [31:0] cmd_arg;
 wire [8:0] volume;
 wire [8:0] brightness;
 wire [3:0] page;
 wire [3:0] photo_index;
 wire [4:0] screen_index;
 wire [4:0] gallery_fade;
 wire [1:0] ui_focus;
 wire [1:0] ui_exhibit;
 wire welcome;
 wire editing;
 wire autoplay;
 wire [5:0] interval_seconds;
 wire [23:0] gui_rgb;
 reg [23:0] scaled_left,scaled_right;
 reg scaled_sample;
 reg [2:0] keys_meta,keys_sync;
 reg shown_ack,shown_valid;
 reg [15:0] shown_index;
 reg [9:0] bg_x,bg_y;
 reg bg_de,bg_vs;
 reg [23:0] bg_rgb;
 reg [7:0] gui_error_q;
 wire [16:0] red_product;
 wire [16:0] green_product;
 wire [16:0] blue_product;
 reg [23:0] scaled_rgb;
 reg scaled_de,scaled_vs;
 reg gui_de,gui_vs,gui_de2,gui_vs2;
 reg render_de,render_vs;reg [9:0] render_x,render_y;
 wire [23:0] gui_rgb_q;
 reg [9:0] wave_x,wave_y;
 wire [23:0] selected_left;
 wire [23:0] selected_right;
 wire signed [33:0] left_product;
 wire signed [33:0] right_product;
 wire axis_valid;
 wire axis_user;
 wire axis_last;
 wire axis_ready;
 wire [23:0] axis_data;
 wire acr_valid;
 wire [19:0] acr_cts;
 wire [19:0] acr_n;
 reg [17:0] edid_wait;
 wire [9:0] tmds0;
 wire [9:0] tmds1;
 wire [9:0] tmds2;
 wire [9:0] tmdsclk;
 assign reset_source=!sys_rst_n || !pll_locked || !power_delay[15];
 assign global_rst=mr[1];
 assign pixel_rst=pr[1];
 assign rst=global_rst || image_mode_m || switch_reset!=0;
 assign image_mode_m=mode_sync[1];
 assign image_rst=global_rst || !image_mode_m || switch_reset!=0;
 assign av_pixel_rst=pixel_rst || image_mode;
 assign image_pixel_rst=pixel_rst || image_reset_p[1];
 assign av_error=sd_error!=0 || ext_error!=0 || demux_error!=0 || audio_error!=0 || memory_error!=0;
 assign cmd_ready=(cmd_opcode!=1 || select_ack_pipe[1]==select_toggle) &&
   ((cmd_opcode!=3 && cmd_opcode!=5) || narration_cmd_ready);
 assign de=image_mode ? img_de : av_de;
 assign vs=image_mode ? img_vs : av_vs;
 assign gui_x=image_mode ? img_x : av_x;
 assign gui_y=image_mode ? img_y : av_y;
 assign error=sd_error!=0 ? sd_error : fs_error!=0 ? fs_error :
  ext_error!=0 ? ext_error : memory_error!=0 ? memory_error : demux_error!=0 ? demux_error : audio_error;
 assign red_product=gui_rgb_q[23:16]*brightness;
 assign green_product=gui_rgb_q[15:8]*brightness;
 assign blue_product=gui_rgb_q[7:0]*brightness;
 assign selected_left=image_mode ? narration_sample : audio_left;
 assign selected_right=image_mode ? narration_sample : audio_right;
 assign left_product=$signed(selected_left)*$signed({1'b0,volume});
 assign right_product=$signed(selected_right)*$signed({1'b0,volume});

clk_wize pll(.refclk(sys_clk),.reset(1'b0),.clk0_out(serial_clk),
  .clk1_out(pixel_raw),.clk2_out(mem_raw),.clk3_out(sdram_raw),.locked(pll_locked));
 EG_LOGIC_BUFG pixel_buffer(.i(pixel_raw),.o(pixel_clk));
 EG_LOGIC_BUFG memory_buffer(.i(mem_raw),.o(mem_clk));
 EG_LOGIC_BUFG sdram_buffer(.i(sdram_raw),.o(sdram_clk));
 
 always @(posedge sys_clk) begin
  if(!sys_rst_n || !pll_locked) power_delay<=0;
  else if(!power_delay[15]) power_delay<=power_delay+1'b1;
 end

always @(posedge mem_clk or posedge reset_source)
  if(reset_source)mr<=3;else mr<={mr[0],1'b0};
 always @(posedge pixel_clk or posedge reset_source)
  if(reset_source)pr<=3;else pr<={pr[0],1'b0};

always @(posedge mem_clk)begin
  if(global_rst)begin mode_sync<=3;mode_last<=1;switch_reset<=0;end
  else begin mode_sync<={mode_sync[0],image_mode};mode_last<=image_mode_m;
   if(mode_last!=image_mode_m)switch_reset<=16'hffff;
   else if(switch_reset!=0)switch_reset<=switch_reset-1'b1;
  end
 end
 
 always @(posedge pixel_clk)image_reset_p<={image_reset_p[0],image_rst};
 
 always @(posedge mem_clk)host_reset_q<=global_rst || switch_reset!=0;

museum_phase1_sdio_host sd(.clk(mem_clk),.rst(host_reset_q),.SD_CLK(SD_CLK),.SD_CMD(SD_CMD),.SD_DAT(SD_DAT),
  .read_req(image_mode_m ? image_host_req : (mounted ? ext_req : fs_req)),.read_lba(image_mode_m ? image_host_lba : (mounted ? ext_lba : fs_lba)),
  .read_count(image_mode_m ? image_host_count : (mounted ? ext_count : 23'd1)),
  .resume_ok(image_mode_m ? image_host_resume : (!prepared || resume_ok)),.ready(ready),.data(sd_data),
  .valid(sd_valid),.done(sd_done),.block_valid(sd_block_valid),.error(sd_error),.debug_state(sd_debug));
 
 always @(posedge mem_clk)begin if(rst)mount_sd_error<=0;else mount_sd_error<=sd_error;end
 museum_phase1_mount #(.MOUNT_ONLY(1)) fs(.clk(mem_clk),.rst(rst),.sd_ready(ready),.sd_error(mount_sd_error),
  .read_req(fs_req),.read_lba(fs_lba),.sd_data(sd_data),
  .sd_valid(!mounted && sd_valid),.sd_done(!mounted && sd_done),
  .mounted(mounted),.error(fs_error),.next_sector(1'b0),.sector_ready(),
  .stream_data(),.stream_valid(),.sector_done(),.file_size(file_size),.debug_state(fs_debug),
  .mount_fat_lba(fat_lba),.mount_data_lba(data_lba),.mount_first_cluster(first_cluster),
  .mount_max_cluster(max_cluster),.mount_spc(spc),.mount_shift(cluster_shift));

fat32_extents ext(.clk(mem_clk),.rst(rst),.mounted(mounted),
  .fat_lba(fat_lba),.data_lba(data_lba),.first_cluster(first_cluster),
  .max_cluster(max_cluster),.spc(spc),.cluster_shift(cluster_shift),
  .read_req(ext_req),.read_lba(ext_lba),.read_count(ext_count),
  .data(sd_data),.valid(mounted && sd_valid),.done(mounted && sd_done),
  .resume_ok(resume_ok),.stream_valid(stream_valid),.stream_data(stream_data),
  .prepared(prepared),.error(ext_error));

av_demux demux(.clk(mem_clk),.rst(rst),.data(stream_data),.valid(stream_valid),
  .sector_commit(sd_block_valid && prepared),.stream_error(av_error),
  .video_resume(video_resume),.audio_resume(audio_resume),.resume_ok(resume_ok),
  .video_data(video_data),.video_valid(video_valid),.video_commit(video_commit),
  .audio_data(audio_data),.audio_valid(audio_valid),.audio_seal(audio_seal),
  .packet_bank(packet_bank),.seal_bank(seal_bank),.error(demux_error));
 museum_phase1_audio audio(.mem_clk(mem_clk),.mem_rst(rst),.data(audio_data),.valid(audio_valid),
  .seal(audio_seal),.packet_bank(packet_bank),.seal_bank(seal_bank),.stream_error(av_error),
  .can_write(audio_resume),.error(audio_error),.pixel_clk(pixel_clk),.pixel_rst(av_pixel_rst),
  .video_started(video_started),.paused(!playing || paused),.sample_valid(audio_sample_valid),.left_data(audio_left),
  .right_data(audio_right),.due_toggle(audio_due_toggle),.due_bank(audio_due_bank),.underflows(audio_underflows));

museum_phase2_video_memory memory(.clk(mem_clk),.rst(rst),.pixel_clk(pixel_clk),.pixel_rst(av_pixel_rst),
  .data(video_data),.valid(video_valid),.resume_ok(video_resume),
  .sector_commit(video_commit),.stream_error(av_error),
  .frame_toggle(frame_toggle),.frame_bank(frame_bank),.display_ack(display_ack),
  .line_toggle(line_toggle),.line_number(line_number),.line_frame_bank(display_bank),
  .pixel_address(pixel_address),.pixel_word(pixel_word),
  .line0_number(line0_number),.line1_number(line1_number),
  .line0_epoch(line0_epoch),.line1_epoch(line1_epoch),
  .line0_ready(line0_ready),.line1_ready(line1_ready),.line_ack(line_ack),.error(memory_error),
  .req(av_req),.is_write(av_write),.bus_addr(av_addr),.bus_data(av_data),
  .memory_ready(memory_ready),.controller_busy(controller_busy),.controller_done(controller_done && !bus_owner),
  .read_valid(controller_read_valid && !bus_owner),.read_data(controller_data),
  .write_take(controller_write_take && !bus_owner),.request_accepted(controller_accept && !bus_client));
 // Memory bus ownership is retained until the physical burst completes.

always @(posedge mem_clk)begin
  if(global_rst)begin bus_owner<=0;bus_pending<=0;bus_client<=0;bus_write_q<=0;bus_addr_q<=0;end
  else begin
   if(!bus_pending && !controller_busy && memory_ready && (image_mode_m ? img_req : av_req))begin
    bus_pending<=1;bus_client<=image_mode_m;
    bus_addr_q<=image_mode_m ? img_addr : av_addr;bus_write_q<=image_mode_m ? img_write : av_write;
   end
   if(controller_accept)begin bus_owner<=bus_client;bus_pending<=0;end
  end
 end
 sdram_burst controller(.clk(mem_clk),.rst(global_rst),
  .req(bus_pending),.write_req(bus_write_q),
  .word_addr(bus_addr_q),.write_data(bus_owner ? img_data : av_data),
  .ready(memory_ready),.busy(controller_busy),.done(controller_done),
  .accept(controller_accept),.read_valid(controller_read_valid),.read_data(controller_data),
  .write_take(controller_write_take),.ras_n(ras_n),.cas_n(cas_n),.we_n(we_n),.addr(addr),.ba(ba),.dq(dq));

museum_sd_service image_sd(.clk(mem_clk),.rst(image_rst),
  .a_req(resource_req),.a_lba(resource_lba),.a_count(resource_sectors),.a_resume(resource_resume),
  .a_ready(resource_ready),.a_data(resource_data),.a_valid(resource_valid),.a_commit(resource_commit),
  .a_done(resource_done),.a_error(resource_sd_error),
  .b_req(narration_req),.b_lba(narration_lba),.b_count(narration_count),.b_resume(narration_resume),
  .b_ready(narration_ready),.b_data(narration_bytes),.b_valid(narration_valid),.b_commit(narration_commit),.b_done(narration_done),.b_error(narration_sd_error),
  .host_req(image_host_req),.host_lba(image_host_lba),.host_count(image_host_count),.host_resume(image_host_resume),
  .host_ready(ready),.host_data(sd_data),.host_valid(sd_valid),.host_commit(sd_block_valid),.host_done(sd_done),.host_error(sd_error));

always @(posedge pixel_clk)begin
  if(pixel_rst)begin image_mode<=1;select_toggle<=0;requested_index<=0;select_ack_pipe<=0;end
  else begin
   select_ack_pipe<={select_ack_pipe[0],select_ack};
   if((page==1 || welcome) && !image_mode)image_mode<=1;
   if(cmd_valid && cmd_ready)begin
    if(cmd_opcode==1)begin image_mode<=1;requested_index<=cmd_arg[15:0];select_toggle<=~select_toggle;end
    else if(cmd_opcode==2)image_mode<=0;
   end
  end
 end
 always @(posedge mem_clk)begin
  if(global_rst)begin select_pipe<=0;select_ack<=0;select_pending<=0;selected_index<=0;end
  else begin
   select_pipe<={select_pipe[0],select_toggle};
   if(select_pipe[1]!=select_ack && !select_pending)begin selected_index<=requested_index;select_pending<=1;end
   if(!image_rst && scan_done && select_pending &&
      ((select_valid && select_ready) || resource_count==0))begin select_pending<=0;select_ack<=select_pipe[1];end
  end
 end
 assign select_valid=scan_done && resource_count!=0 && (select_pending || !auto_loaded);
 always @(posedge mem_clk)begin
  if(image_rst)begin scan_started<=0;scan_start<=0;auto_loaded<=0;end
  else begin
   scan_start<=0;
   if(ready && !scan_started)begin scan_start<=1;scan_started<=1;end
   if(select_valid && select_ready)auto_loaded<=1;
  end
 end
 wire [1:0] audio_cache_select;
 wire [3:0] audio_cache_present;
 wire [31:0] audio_cache_cluster,audio_cache_size,audio_cache_fat,audio_cache_data,audio_cache_max;
 wire [7:0] audio_cache_spc,audio_cache_error;wire [2:0] audio_cache_shift;
 museum_phase6_resources #(.CACHE_AUDIO(EXTERNAL_GESTURE)) resources(.mem_clk(mem_clk),.mem_rst(image_rst),.scan_start(scan_start),
  .audio_raddr(audio_cache_select),.audio_present(audio_cache_present),.audio_cluster(audio_cache_cluster),
  .audio_size(audio_cache_size),.audio_fat_lba(audio_cache_fat),.audio_data_lba(audio_cache_data),
  .audio_max_cluster(audio_cache_max),.audio_spc(audio_cache_spc),.audio_shift(audio_cache_shift),.audio_scan_error(audio_cache_error),
  .select_valid(select_valid),.select_index(select_pending ? selected_index : 16'd0),.select_ready(select_ready),
  .resource_count(resource_count),.scan_done(scan_done),.busy(resource_busy),.error(resource_error),
  .rd_req_valid(resource_req),.rd_lba(resource_lba),.rd_count(resource_sectors),.rd_req_ready(resource_ready),
  .rd_data(resource_data),.rd_valid(resource_valid),.rd_sector_commit(resource_commit),.rd_done(resource_done),.rd_error(resource_sd_error),.rd_resume(resource_resume),
  .image_begin_valid(image_begin),.image_begin_ready(image_begin_ready),.image_index(image_index),.image_width(image_width),.image_height(image_height),
  .pixel_valid(image_pixel_valid),.pixel_ready(image_pixel_ready),.pixel_addr(image_pixel_addr),.pixel_rgb(image_pixel_rgb),
  .image_end_valid(image_end),.image_end_ready(image_end_ready),.image_abort(image_abort));

museum_gallery_image_memory image_memory(.clk(mem_clk),.rst(image_rst),.pixel_clk(pixel_clk),.pixel_rst(image_pixel_rst),.zoom(gallery_zoom),
  .begin_valid(image_begin),.begin_ready(image_begin_ready),.image_index(image_index),.image_width(image_width),.image_height(image_height),
  .pixel_valid(image_pixel_valid),.pixel_ready(image_pixel_ready),.pixel_addr(image_pixel_addr),.pixel_rgb(image_pixel_rgb),
  .end_valid(image_end),.end_ready(image_end_ready),.abort(image_abort),
  .frame_toggle(img_frame_toggle),.frame_bank(img_frame_bank),.display_ack(img_display_ack),.active_index(image_active_index),.error(image_memory_error),
  .line_toggle(img_line_toggle),.line_number(img_line_number),.line_frame_bank(img_display_bank),
  .pixel_address(img_pixel_address),.pixel_word(img_pixel_word),.line0_number(img_line0_number),.line1_number(img_line1_number),
  .line0_epoch(img_line0_epoch),.line1_epoch(img_line1_epoch),.line0_ready(img_line0_ready),.line1_ready(img_line1_ready),.line_ack(img_line_ack),
  .req(img_req),.write_req(img_write),.word_addr(img_addr),.write_data(img_data),.memory_ready(memory_ready),
  .controller_busy(controller_busy),.controller_done(controller_done && bus_owner),
  .read_valid(controller_read_valid && bus_owner),.read_data(controller_data),
  .write_take(controller_write_take && bus_owner),.request_accepted(controller_accept && bus_client));
 
 museum_gallery_image_display #(.SHOW_STATUS(0)) image_display(.clk(pixel_clk),.rst(image_pixel_rst),.zoom(gallery_zoom),
  .frame_toggle(img_frame_toggle),.frame_bank(img_frame_bank),.display_ack(img_display_ack),.display_bank(img_display_bank),
  .line_toggle(img_line_toggle),.line_number(img_line_number),.line_ack(img_line_ack),
  .line0_number(img_line0_number),.line1_number(img_line1_number),.line0_epoch(img_line0_epoch),.line1_epoch(img_line1_epoch),
  .line0_ready(img_line0_ready),.line1_ready(img_line1_ready),.pixel_address(img_pixel_address),.pixel_word(img_pixel_word),
  .error_async(8'd0),.mounted_async(scan_done),.sd_stage_async(4'd0),.fs_stage_async(8'd0),
  .audio_due_toggle(1'b0),.audio_due_bank(2'd0),.audio_underflows(8'd0),.display_error(),.video_started(img_started),
  .x(img_x),.y(img_y),.hs(img_hs),.vs(img_vs),.de(img_de),.rgb(img_rgb));

always @(posedge pixel_clk)begin
  count_meta<=resource_count;index_meta<=image_active_index;busy_meta<=resource_busy || !scan_done;
  count_p<=count_meta;index_p<=index_meta;busy_p<=busy_meta;
  image_error_meta<=sd_error!=0 ? sd_error : resource_error!=0 ? resource_error : image_memory_error;
  image_error_p<=image_error_meta;
 end

 EG_PHY_SDRAM_2M_32 physical_sdram(.clk(sdram_clk),.cke(1'b1),.cs_n(1'b0),
  .ras_n(ras_n),.cas_n(cas_n),.we_n(we_n),.addr(addr),.ba(ba),.dq(dq),
  .dm0(1'b0),.dm1(1'b0),.dm2(1'b0),.dm3(1'b0));

reg [7:0] diagnostic_error_q;reg [4:0] diagnostic_fs_q;reg [3:0] diagnostic_sd_q;
 always @(posedge mem_clk)begin
  diagnostic_error_q<=error;diagnostic_fs_q<=fs_debug;diagnostic_sd_q<=sd_debug;
  if(rst)begin first_error<=0;first_fs_stage<=0;first_sd_stage<=0;end
  else if(first_error==0 && diagnostic_error_q!=0)begin
   first_error<=diagnostic_error_q;first_fs_stage<={3'b000,diagnostic_fs_q};first_sd_stage<=diagnostic_sd_q;
  end
 end
 museum_phase1_display #(.SHOW_STATUS(0)) display(.display_error(av_display_error),.x(av_x),.y(av_y),.clk(pixel_clk),.rst(av_pixel_rst),.frame_toggle(frame_toggle),.frame_bank(frame_bank),
  .display_ack(display_ack),.display_bank(display_bank),
  .line_toggle(line_toggle),.line_number(line_number),.line_ack(line_ack),
  .line0_number(line0_number),.line1_number(line1_number),
  .line0_epoch(line0_epoch),.line1_epoch(line1_epoch),
  .line0_ready(line0_ready),.line1_ready(line1_ready),
  .pixel_address(pixel_address),.pixel_word(pixel_word),.error_async(first_error),
  .sd_stage_async(first_sd_stage),.fs_stage_async(first_fs_stage),
  .mounted_async(prepared),.audio_due_toggle(audio_due_toggle),.audio_due_bank(audio_due_bank),
  .audio_underflows(audio_underflows),.video_started(video_started),.hs(av_hs),.vs(av_vs),.de(av_de),.rgb(av_rgb));

always @(posedge pixel_clk)begin keys_meta<={KEY4_N,KEY3_N,KEY2_N};keys_sync<=keys_meta;end
 museum_keys keys(.pixel_clk(pixel_clk),.pixel_rst(pixel_rst || (EXTERNAL_GESTURE && gesture_keys_blocked)),.keys_n(keys_sync),.events(key_events));
 museum_phase2_control controls(.clk(pixel_clk),.rst(pixel_rst),
  .cmd_valid(cmd_valid && cmd_ready),.cmd_opcode(cmd_opcode),.cmd_arg(cmd_arg),
  .playing(playing),.paused(paused),.volume(volume),.brightness(brightness),.command_error(command_error));
 museum_narration_player #(.USE_CACHED_INDEX(EXTERNAL_GESTURE)) narration(
  .cached_done(scan_done),.cached_error(audio_cache_error),.cached_present(audio_cache_present),
  .cached_cluster(audio_cache_cluster),.cached_size(audio_cache_size),.cached_fat_lba(audio_cache_fat),
  .cached_data_lba(audio_cache_data),.cached_max_cluster(audio_cache_max),
  .cached_spc(audio_cache_spc),.cached_shift(audio_cache_shift),.cached_select(audio_cache_select),
  .mem_clk(mem_clk),.mem_rst(image_rst),.pixel_clk(pixel_clk),.pixel_rst(image_pixel_rst),
  .cmd_start(cmd_valid && cmd_ready && cmd_opcode==3),
  .cmd_stop(cmd_valid && cmd_ready && cmd_opcode==5),
  .exhibit(cmd_arg[1:0]),.paused(paused),.cmd_ready(narration_cmd_ready),
  .playing(narration_playing),.busy(narration_busy),.ended(narration_ended),.error(narration_error),
  .sample_valid(narration_sample_valid),.sample_data(narration_sample),.content_valid(),
  .consumed_samples(),.underflows(),
  .rd_req_valid(narration_req),.rd_lba(narration_lba),.rd_count(narration_count),.rd_req_ready(narration_ready),
  .rd_data(narration_bytes),.rd_valid(narration_valid),.rd_sector_commit(narration_commit),
  .rd_done(narration_done),.rd_error(narration_sd_error),.rd_resume(narration_resume));
 
 always @(posedge pixel_clk)begin
  if(image_pixel_rst)begin shown_ack<=0;shown_valid<=0;shown_index<=0;end
  else if(img_display_ack!=shown_ack)begin
   shown_ack<=img_display_ack;shown_index<=index_p;shown_valid<=1;
  end
 end
 museum_phase6_ui ui(.clk(pixel_clk),.rst(pixel_rst),.frame_start(bg_x==0 && bg_y==480),.carousel_enabled(carousel_enabled),.gesture_enabled(EXTERNAL_GESTURE && gesture_enabled),
  .events(key_events!=0 ? key_events : (EXTERNAL_GESTURE ? gesture_events : 8'd0)),.image_mode(image_mode),.media_playing(page==4 ? narration_playing : playing),.media_paused(paused),
  .audio_busy(narration_busy),
  .media_busy(busy_p),.resource_count(count_p),.shown_index(shown_index),.shown_valid(shown_valid),
  .media_error(page==4 && narration_error!=0 ? narration_error : gui_error_q),.volume(volume),.brightness(brightness),
  .page(page),.focus(ui_focus),.exhibit(ui_exhibit),.editing(editing),.autoplay(autoplay),
  .interval_seconds(interval_seconds),.welcome(welcome),.screen_index(screen_index),
  .photo_index(photo_index),.zoom(gallery_zoom),.fade_level(gallery_fade),
  .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_opcode(cmd_opcode),.cmd_arg(cmd_arg),.nav_ready(gesture_ready));
 museum_phase6_render renderer(.clk(pixel_clk),.rst(pixel_rst),.x(bg_x),.y(bg_y),.active(bg_de),
  .base_rgb(bg_rgb),.page(page),.focus(ui_focus),.gesture_enabled(EXTERNAL_GESTURE && gesture_enabled),.editing(editing),.autoplay(autoplay && carousel_enabled),
  .photo_index(photo_index),.zoom(gallery_zoom),.fade_level(gallery_fade),
  .interval_seconds(interval_seconds),.volume(volume),.brightness(brightness),
  .image_mode(image_mode),.playing(playing),.paused(paused),
  .screen_visible(shown_valid && shown_index=={11'd0,screen_index}),.frame_valid(shown_valid),
  .media_error(gui_error_q),.out_rgb(gui_rgb));
 
 always @(posedge pixel_clk)begin
  bg_x<=gui_x;bg_y<=gui_y;bg_de<=de;bg_vs<=vs;
  bg_rgb<=image_mode ? img_rgb : playing ? av_rgb : 24'h000000;
  gui_error_q<=command_error!=0 ? command_error : image_mode ? image_error_p : av_display_error;
 end
 // Register pixel scaling and delay DE/VS by the same cycle.

always @(posedge pixel_clk)begin
 render_x<=bg_x;render_y<=bg_y;wave_x<=render_x;wave_y<=render_y;
 if(pixel_rst)begin render_de<=0;render_vs<=1;end
 else begin render_de<=bg_de;render_vs<=bg_vs;end
end
 reg [9:0] clock_x,clock_y;
 always @(posedge pixel_clk)begin clock_x<=wave_x;clock_y<=wave_y;end
 wire [23:0] clock_rgb;
 assign gui_rgb_q=EXTERNAL_GESTURE ? gesture_overlay_rgb : clock_rgb;
 assign gesture_pixel_clk=pixel_clk;assign gesture_pixel_rst=pixel_rst;
 assign gesture_de=gui_de2;assign gesture_x=clock_x;assign gesture_y=clock_y;
 assign gesture_base_rgb=clock_rgb;assign gesture_page=page;
 assign gesture_frame_start=bg_x==0 && bg_y==480;
 wire [23:0] wave_base_rgb;
 museum_floating_clock floating_clock(.clk(pixel_clk),.rst(pixel_rst),
  .x(clock_x),.y(clock_y),.active(gui_de2),.enabled(clock_enabled),.base_rgb(wave_base_rgb),.out_rgb(clock_rgb));
 museum_audio_waveform waveform(.clk(pixel_clk),.rst(pixel_rst),.x(wave_x),.y(wave_y),
  .active(gui_de),.base_rgb(gui_rgb),.enabled(image_mode && page==4),
  .paused(paused),.loading(narration_busy),.ended(narration_ended),.error(narration_error),
  .sample_valid(scaled_sample),.sample_data(scaled_left),
  .clear(cmd_valid && cmd_ready && (cmd_opcode==3 || cmd_opcode==5)),.out_rgb(wave_base_rgb));
 always @(posedge pixel_clk)begin if(pixel_rst)begin gui_de<=0;gui_vs<=1;gui_de2<=0;gui_vs2<=1;end else begin gui_de<=render_de;gui_vs<=render_vs;gui_de2<=gui_de;gui_vs2<=gui_vs;end end
 always @(posedge pixel_clk) begin
  if(pixel_rst)begin scaled_rgb<=0;scaled_de<=0;scaled_vs<=1;end
  else begin scaled_rgb<={red_product[15:8],green_product[15:8],blue_product[15:8]};scaled_de<=gui_de2;scaled_vs<=gui_vs2;end
 end

always @(posedge pixel_clk)begin
  if(pixel_rst)begin scaled_left<=0;scaled_right<=0;scaled_sample<=0;end
  else begin scaled_left<=left_product[31:8];scaled_right<=right_product[31:8];scaled_sample<=image_mode ? narration_sample_valid : audio_sample_valid;end
 end

video_axis adapter(.clk(pixel_clk),.rst(pixel_rst),.de(scaled_de),.vs(scaled_vs),.rgb(scaled_rgb),
  .valid(axis_valid),.user(axis_user),.last(axis_last),.data(axis_data));

audio_arc_calculate acr(.I_clk(pixel_clk),.I_rst(pixel_rst),.I_audio_valid(scaled_sample),
  .O_acr_valid(acr_valid),.O_acr_cts(acr_cts),.O_acr_n(acr_n));
 
 always @(posedge pixel_clk) if(pixel_rst) edid_wait<=0;
 else if(edid_wait!=100001) edid_wait<=edid_wait+1'b1;
 
 hdmi_1_4b_transmitter_core_wrapper #(.DEVICE("EG"),
  .HTOTAL(800),.HSA(96),.HFP(16),.HBP(48),.HACTIVE(640),
  .VTOTAL(525),.VSA(2),.VFP(10),.VBP(33),.VACTIVE(480),
  .VIDEO_VIC(1),.VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),
  .AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(250)) hdmi(
  .I_pixel_clk(pixel_clk),.I_rst(pixel_rst),.I_edid_read_trig(edid_wait==100000),
  .O_edid_read_valid(),.O_edid_read_data(),
  .I_axis_s_user(axis_user),.I_axis_s_valid(axis_valid),.I_axis_s_last(axis_last),
  .I_axis_s_data(axis_data),.O_axis_s_ready(axis_ready),
  .I_audio_valid(scaled_sample),.I_audio_left_data(scaled_left),.I_audio_right_data(scaled_right),
  .I_acr_valid(acr_valid),.I_acr_cts(acr_cts),.I_acr_n(acr_n),.O_video_locked(),
  .O_ddc_scl(HDMI_DDC_SCL),.IO_ddc_sda(HDMI_DDC_SDA),
  .O_ch0_tmds_data(tmds0),.O_ch1_tmds_data(tmds1),.O_ch2_tmds_data(tmds2),.O_clk_tmds_data(tmdsclk));
 hdmi_phy_wrapper #(.DEVICE("EG")) phy(.I_pixel_clk(pixel_clk),.I_serial_clk(serial_clk),.I_rst(pixel_rst),
  .I_tmds_channel_0(tmds0),.I_tmds_channel_1(tmds1),.I_tmds_channel_2(tmds2),.I_tmds_channel_clk(tmdsclk),
  .O_tmds_ch0_p(HDMI_D0_P),.O_tmds_ch1_p(HDMI_D1_P),.O_tmds_ch2_p(HDMI_D2_P),.O_tmds_clk_p(HDMI_CLK_P));
endmodule

// Preserve the original standalone top-level pins and default behavior.
module museum_phase6_top(input sys_clk,sys_rst_n,KEY2_N,KEY3_N,KEY4_N,SW4,
 output SD_CLK,inout SD_CMD,input [3:0] SD_DAT,
 output HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,HDMI_DDC_SCL,inout HDMI_DDC_SDA);
 museum_phase6_core core(.sys_clk(sys_clk),.sys_rst_n(sys_rst_n),.KEY2_N(KEY2_N),.KEY3_N(KEY3_N),.KEY4_N(KEY4_N),.SW4(SW4),
 .SD_CLK(SD_CLK),.SD_CMD(SD_CMD),.SD_DAT(SD_DAT),.HDMI_CLK_P(HDMI_CLK_P),.HDMI_D2_P(HDMI_D2_P),
 .HDMI_D1_P(HDMI_D1_P),.HDMI_D0_P(HDMI_D0_P),.HDMI_DDC_SCL(HDMI_DDC_SCL),.HDMI_DDC_SDA(HDMI_DDC_SDA),
 .clock_enabled(1'b1),.gesture_enabled(1'b0),.gesture_events(8'd0),.gesture_overlay_rgb(24'd0),.gesture_keys_blocked(1'b0),
 .gesture_pixel_clk(),.gesture_pixel_rst(),.gesture_de(),.gesture_frame_start(),.gesture_ready(),
 .gesture_x(),.gesture_y(),.gesture_base_rgb(),.gesture_page());
endmodule

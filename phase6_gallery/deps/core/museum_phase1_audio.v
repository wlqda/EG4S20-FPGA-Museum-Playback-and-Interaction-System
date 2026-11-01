// Three CRC-sealed PCM banks. Unread banks cannot be overwritten.
// HDMI sampling continues at 48 kHz during starvation, emitting silence while
// holding the content position. Picture switches follow the resumed content.
module museum_phase1_audio #(parameter SAMPLES=1920,PIXEL_HZ=25000000,SAMPLE_HZ=48000)(
 input mem_clk,mem_rst,input [7:0] data,input valid,seal,
 input [1:0] packet_bank,seal_bank,input stream_error,output can_write,output reg [7:0] error,
 input pixel_clk,pixel_rst,video_started,paused,
 output reg sample_valid,output reg [23:0] left_data,right_data,
 output reg due_toggle,output reg [1:0] due_bank,output reg [7:0] underflows);
 // Only banks 0..2 exist; each bank reserves 2048 words for 1920 samples.
 (* ram_style="bram_32k" *) reg [31:0] pcm01[0:4095];
 // Same third 2048-word stereo bank, split into unchanged 16-bit channels.
 // One 32K block holds the left channel; the right uses the 9K blocks.
 (* ram_style="bram_32k" *) reg [15:0] pcm2_left[0:2047];
 (* ram_style="bram_9k" *) reg [15:0] pcm2_right[0:2047];
 reg [23:0] assembly;
 reg [1:0] byte_phase;
 reg [10:0] write_index,read_index;
 reg [1:0] read_bank;
 reg [2:0] ready_banks,free_toggle,free0,free1,free_seen,ready0,ready1;
 reg [31:0] read_word01;reg [15:0] read_left2,read_right2;reg read_is2;
 wire [31:0] read_word2={read_right2,read_left2};
 wire [31:0] read_word=read_is2 ? read_word2 : read_word01;
 reg [1:0] bad_sync;
 reg [24:0] phase;
 wire [25:0] next_phase={1'b0,phase}+SAMPLE_HZ;
 reg started,need_due,starving;
 assign can_write=!ready_banks[packet_bank] && error==0 && !stream_error;
 integer b;
 always @(posedge mem_clk) begin
  if(mem_rst) begin
   assembly<=0;byte_phase<=0;write_index<=0;ready_banks<=0;
   free0<=0;free1<=0;free_seen<=0;error<=0;
  end else begin
   free0<=free_toggle;free1<=free0;
   for(b=0;b<3;b=b+1) if(free1[b]!=free_seen[b]) begin
    ready_banks[b]<=0;free_seen[b]<=free1[b];
   end
   if(valid && !stream_error && error==0) begin
    if(!can_write || write_index>=SAMPLES) error<=8'h62;
    else begin
     case(byte_phase)
      0:assembly[7:0]<=data;
      1:assembly[15:8]<=data;
      2:assembly[23:16]<=data;
      3:begin
      if(packet_bank<2)pcm01[{packet_bank[0],write_index}]<={data,assembly};
      else if(packet_bank==2)begin
       pcm2_left[write_index]<=assembly[15:0];
       pcm2_right[write_index]<={data,assembly[23:16]};
      end
      write_index<=write_index+1'b1;
     end
     endcase
     byte_phase<=byte_phase+1'b1;
    end
   end
   if(seal && !stream_error && error==0) begin
    if(write_index!=SAMPLES || byte_phase!=0 || ready_banks[seal_bank]) error<=8'h62;
    else begin ready_banks[seal_bank]<=1;write_index<=0;end
   end
  end
 end
 always @(posedge pixel_clk)begin
  read_word01<=pcm01[{read_bank[0],read_index}];
  read_left2<=pcm2_left[read_index];read_right2<=pcm2_right[read_index];
  read_is2<=read_bank==2;
 end
 always @(posedge pixel_clk) begin
  if(pixel_rst) begin
   ready0<=0;ready1<=0;bad_sync<=0;phase<=0;read_bank<=0;read_index<=0;
   started<=0;need_due<=0;starving<=0;free_toggle<=0;due_toggle<=0;due_bank<=0;
   sample_valid<=0;left_data<=0;right_data<=0;underflows<=0;
  end else begin
   ready0<=ready_banks;ready1<=ready0;bad_sync<={bad_sync[0],stream_error || error!=0};
   sample_valid<=0;
   if(video_started) started<=1;
   if(next_phase>=PIXEL_HZ) begin
    phase<=next_phase-PIXEL_HZ;sample_valid<=1;left_data<=0;right_data<=0;
    if(started && !bad_sync[1] && !paused) begin
     if(ready1[read_bank]) begin
      left_data<={read_word[15:0],8'b0};right_data<={read_word[31:16],8'b0};starving<=0;
      if(need_due) begin due_toggle<=~due_toggle;due_bank<=read_bank;need_due<=0;end
      if(read_index==SAMPLES-1) begin
       free_toggle[read_bank]<=~free_toggle[read_bank];read_index<=0;
       read_bank<=read_bank==2 ? 0 : read_bank+1'b1;need_due<=1;
      end else read_index<=read_index+1'b1;
     end else begin
      starving<=1;
      if(!starving && underflows!=255) underflows<=underflows+1'b1;
     end
    end
   end else phase<=next_phase[24:0];
  end
 end
endmodule

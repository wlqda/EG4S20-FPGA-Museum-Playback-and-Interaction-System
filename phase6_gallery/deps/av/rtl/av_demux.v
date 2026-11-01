// A frame is 900 RGB565 sectors followed by 15 stereo PCM16LE sectors.
// The last video commit is withheld until all audio sectors also pass CRC.
module av_demux #(parameter VIDEO_SECTORS=900,AUDIO_SECTORS=15)(
 input clk,rst,input [7:0] data,input valid,sector_commit,stream_error,
 input video_resume,audio_resume,output resume_ok,
 output [7:0] video_data,audio_data,output video_valid,audio_valid,
 output reg video_commit,audio_seal,output reg [1:0] packet_bank,seal_bank,
 output reg [7:0] error);
 reg [9:0] sector,bytes_in_sector;
 // Phase only changes at an accepted sector boundary. Keeping it as state
 // removes the sector comparator from every video-byte/FIFO push path.
 reg audio_phase;
 assign resume_ok=!stream_error && error==0 && (audio_phase ? audio_resume : video_resume);
 assign video_data=data;
 assign audio_data=data;
 assign video_valid=valid && !audio_phase && !stream_error && error==0;
 assign audio_valid=valid && audio_phase && !stream_error && error==0;
 always @(posedge clk) begin
  if(rst) begin sector<=0;audio_phase<=VIDEO_SECTORS==0;bytes_in_sector<=0;packet_bank<=0;seal_bank<=0;error<=0;video_commit<=0;audio_seal<=0;end
  else begin
   video_commit<=0;audio_seal<=0;
   if(!stream_error && error==0) begin
    if(valid) begin
     if(bytes_in_sector==512) error<=8'h61;
     else bytes_in_sector<=bytes_in_sector+1'b1;
    end
    if(sector_commit) begin
     if(bytes_in_sector!=512 || valid) error<=8'h61;
     else begin
      bytes_in_sector<=0;
      if(sector<VIDEO_SECTORS-1) video_commit<=1;
      if(sector==VIDEO_SECTORS+AUDIO_SECTORS-1) begin
       video_commit<=1;audio_seal<=1;seal_bank<=packet_bank;sector<=0;audio_phase<=VIDEO_SECTORS==0;
       packet_bank<=packet_bank==2 ? 0 : packet_bank+1'b1;
      end else begin
       sector<=sector+1'b1;
       if(sector==VIDEO_SECTORS-1)audio_phase<=1;
      end
     end
    end
   end
  end
 end
endmodule

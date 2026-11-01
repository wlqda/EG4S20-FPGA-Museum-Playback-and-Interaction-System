// Streaming RIFF/WAVE PCM decoder. Only committed sector bytes may enter.
// 48 kHz, signed little-endian PCM16 mono; ignores unknown chunks + odd padding.
module museum_wav_parser(
 input clk,rst,start,input [31:0] file_size,
 input [7:0] in_data,input in_valid,in_last,output in_ready,
 output reg [15:0] pcm_data,output reg pcm_valid,pcm_last,input pcm_ready,
 output reg [31:0] total_samples,output reg done,output reg [7:0] error);
 localparam HEAD=0,CHUNK=1,FMT=2,CHECK=3,SKIP=4,PAD=5,DATA=6,END=7,FAIL=8,FMT_WAIT=9;
 reg [3:0] state;
 reg [31:0] position,riff_end,acc,chunk_id,remaining;
 reg [4:0] offset;
 reg fmt_seen,pad_needed,half_sample;
 reg [7:0] low_byte;
 reg [7:0] fmt [0:15];
 wire [31:0] word_in={in_data,acc[31:8]};
 assign in_ready=state!=CHECK && state!=FMT_WAIT && state!=END && state!=FAIL &&
                 (!pcm_valid || pcm_ready);
 reg format_bad;
 // file_size is fixed before byte seven of the RIFF header. Separate the
 // subtraction from the comparison driving parser state/reset controls.
 reg [31:0] file_payload_limit;
 reg file_too_short;
 always @(posedge clk)begin
  file_payload_limit<=file_size-32'd8;
  file_too_short<=file_size<32'd12;
 end
 always @(posedge clk)format_bad<=({fmt[1],fmt[0]}!=16'd1 || {fmt[3],fmt[2]}!=16'd1 ||
       {fmt[7],fmt[6],fmt[5],fmt[4]}!=32'd48000 ||
       {fmt[11],fmt[10],fmt[9],fmt[8]}!=32'd96000 ||
       {fmt[13],fmt[12]}!=16'd2 || {fmt[15],fmt[14]}!=16'd16);
 task fail;input [7:0] code;begin state<=FAIL;error<=code;pcm_valid<=0;end endtask
 always @(posedge clk)begin
  if(rst || start)begin
   state<=HEAD;position<=0;riff_end<=0;acc<=0;chunk_id<=0;remaining<=0;offset<=0;
   fmt_seen<=0;pad_needed<=0;half_sample<=0;low_byte<=0;
   pcm_data<=0;pcm_valid<=0;pcm_last<=0;total_samples<=0;done<=0;error<=0;
  end else begin
   if(pcm_valid && pcm_ready)pcm_valid<=0;
   if(state==FMT_WAIT)state<=CHECK;
   if(state==CHECK)begin
    if(format_bad)
      fail(8'h82);
    else begin fmt_seen<=1;offset<=0;state<=pad_needed ? PAD : CHUNK;end
   end
   if(in_valid && in_ready)begin
    position<=position+1'b1;acc<=word_in;
    case(state)
     HEAD:begin
      offset<=offset+1'b1;
      if(offset==3 && word_in!=32'h46464952)fail(8'h80);
      if(offset==7)begin
       riff_end<=word_in+8;
       if(file_too_short || word_in<4 || word_in>file_payload_limit)fail(8'h81);
      end
      if(offset==11)begin
       if(word_in!=32'h45564157)fail(8'h80);
       else begin state<=CHUNK;offset<=0;end
      end
     end
     CHUNK:begin
      offset<=offset+1'b1;
      if(position>=riff_end)fail(8'h81);
      else if(offset==3)chunk_id<=word_in;
      else if(offset==7)begin
       offset<=0;remaining<=word_in;pad_needed<=word_in[0];half_sample<=0;
       if(word_in>riff_end-position-1 ||
          (word_in[0] && word_in==riff_end-position-1))fail(8'h81);
       else if(chunk_id==32'h20746d66)begin
        if(word_in<16 || fmt_seen)fail(8'h82);else state<=FMT;
       end else if(chunk_id==32'h61746164)begin
        if(!fmt_seen || word_in==0 || word_in[0])fail(8'h83);
        else begin total_samples<=word_in>>1;state<=DATA;end
       end else if(word_in==0)state<=CHUNK;
       else state<=SKIP;
      end
     end
     FMT:begin
      if(offset<16)begin fmt[offset]<=in_data;offset<=offset+1'b1;end
      remaining<=remaining-1'b1;
      if(remaining==1)state<=FMT_WAIT;
     end
     SKIP:begin
      remaining<=remaining-1'b1;
      if(remaining==1)begin state<=pad_needed ? PAD : CHUNK;offset<=0;end
     end
     PAD:begin state<=CHUNK;offset<=0;end
     DATA:begin
      remaining<=remaining-1'b1;half_sample<=~half_sample;
      if(!half_sample)low_byte<=in_data;
      else begin pcm_data<={in_data,low_byte};pcm_valid<=1;pcm_last<=remaining==1;end
      if(remaining==1)begin done<=1;state<=END;end
     end
     default:fail(8'h81);
    endcase
    if(in_last && !(state==DATA && remaining==1))fail(8'h81);
   end
  end
 end
endmodule

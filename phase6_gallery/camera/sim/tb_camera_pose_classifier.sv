`timescale 1ns/1ps
module tb_camera_pose_classifier #(parameter EDGE=0);
 reg clk=0;always #5 clk=~clk;
 reg rst=1,clear_models=0,enabled=1,capture=0,sample_valid=0,candidate_valid=1,clipped=0;
 reg [31:0] frame_id=0;reg [143:0] counts=0;reg [12:0] area=100;
 reg [3:0] edges=0;
 wire model_ready,collecting,pose_valid,armed,event_valid;
 wire [2:0] stage,error,pose,event_direction;wire [31:0] event_sequence;wire [12:0] best_distance;
 reg passed=0;integer pulses=0;reg [2:0] last_event=0;
 camera_pose_classifier #(.STALE_CYCLES(5000),.UNCERTAIN_CYCLES(1800),.EXCURSION_CYCLES(20000),.ALLOW_WRIST_EDGE(EDGE)) dut(.*);
 always @(posedge clk)if(event_valid)begin pulses=pulses+1;last_event=event_direction;end
 task tick(input integer n);begin repeat(n)@(negedge clk);end endtask
 task check(input bit ok,input string message);begin if(!ok)$fatal(1,"%s stage=%d pose=%d error=%d pulses=%d",message,stage,pose,error,pulses);end endtask
 function [143:0] shape(input integer p);
  reg [143:0] v;integer a,b;begin
   case(p) 0:begin a=5;b=6;end 1:begin a=9;b=10;end
    2:begin a=4;b=5;end 3:begin a=7;b=6;end
    4:begin a=1;b=5;end 5:begin a=13;b=9;end default:begin a=0;b=3;end endcase
   v=0;v[a*9+:9]=80;v[b*9+:9]=20;
   if(p==6)begin v=0;v[5*9+:9]=40;v[6*9+:9]=10;v[9*9+:9]=40;v[10*9+:9]=10;end
   shape=v;
  end
 endfunction
 task feed(input integer p);begin
  frame_id=frame_id+1;counts=shape(p);sample_valid=1;tick(1);sample_valid=0;tick(800);
 end endtask
 task start_capture;begin capture=1;tick(1);capture=0;tick(1);end endtask
 task train(input integer p);begin start_capture();feed(p);feed(p);feed(p);end endtask
 task neutral;begin feed(0);feed(6);feed(1);end endtask
 initial begin
  tick(4);rst=0;tick(2);
  if(EDGE)begin
   clipped=1;edges=3;start_capture();feed(0);feed(0);feed(0);check(stage==0,"two clipped edges cannot train a wrist entry");
   edges=1;
  end
  start_capture();feed(0);feed(1);feed(0);check(stage==0,"unstable calibration must not complete");
  feed(0);feed(0);check(stage==1,"three stable samples train N0");
  check(dut.templates[5]==204 && dut.templates[6]==51,"normalization and averaging");
  train(1);check(stage==2,"second neutral");
  train(0);check(stage==2 && error==2 && !collecting,"reject direction identical to neutral");
  train(6);check(stage==2 && error==2,"reject direction inside neutral roll envelope");
  train(2);train(3);train(4);check(!model_ready && pulses==0,"incomplete models cannot navigate");
  train(5);check(stage==6 && model_ready,"six real templates ready");
  neutral();check(armed && pose==1,"both neutral appearances arm together");
  feed(2);feed(2);check(pulses==1 && last_event==2 && !armed,"left once");
  feed(2);feed(2);feed(3);feed(3);check(pulses==1,"hold and direct direction change cannot repeat");
  neutral();feed(3);feed(3);check(pulses==2 && last_event==3,"neutral rearms right");
  neutral();feed(8);feed(8);feed(8);feed(4);feed(4);check(pulses==2,"prolonged unknown cancels readiness");
  neutral();clipped=1;edges=EDGE ? 2 : 0;feed(0);clipped=EDGE;edges=EDGE ? 1 : 0;
  feed(5);feed(5);check(pulses==2,"new clipped edge cancels");
  neutral();candidate_valid=0;feed(0);candidate_valid=1;feed(5);feed(5);check(pulses==2,"lost hand cancels");
  neutral();tick(5100);check(!armed && pose==0,"stale timeout");
  feed(0);feed(0); // duplicates must not supply the third neutral
  sample_valid=1;tick(1);sample_valid=0;tick(800);check(!armed,"duplicate source id ignored");
  frame_id=frame_id-1;sample_valid=1;tick(1);sample_valid=0;tick(800);check(!armed,"old source id ignored");
  frame_id=frame_id+1;feed(0);check(armed,"new third neutral arms");
  feed(4);feed(4);check(pulses==3 && last_event==4,"up event");
  neutral();feed(5);feed(5);check(pulses==4 && last_event==5,"down event");
  neutral();feed(8);feed(2);feed(2);check(pulses==5,"brief ambiguous transition permits a bounded excursion");
  enabled=0;tick(2);frame_id=0;enabled=1;neutral();check(armed,"fresh sequence after source restart");
  clear_models=1;tick(1);clear_models=0;tick(2);check(!model_ready && stage==0 && !armed,"clear calibration");
  passed=1;$display("PASS pose classifier: calibration rejection, normalization, two neutrals, four one-shot events, loss, replay, timeout");$finish;
 end
 initial begin #3000000;$fatal(1,"watchdog");end
endmodule

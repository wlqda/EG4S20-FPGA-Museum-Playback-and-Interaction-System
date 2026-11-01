// Large hexadecimal diagnostics on the red error screen. Coordinates follow
// the registered HDMI pixel, so the overlay does not change video timing.
module error_overlay #(parameter VERSION_DIGIT="6")(input [9:0] x,y,input [7:0] code,fs_stage,
 input [3:0] sd_stage,output ink);
 reg [7:0] character;
 reg [9:0] local_x,local_y;
 reg area_active;
 wire [2:0] character_cell=local_x[8:6],column=local_x[5:3],row=local_y[5:3];
 function [7:0] hex_char;
  input [3:0] value;
  begin hex_char=value<10 ? "0"+value : "A"+value-10;end
 endfunction
 function [34:0] glyph;
  input [7:0] c;
  begin case(c)
   "0":glyph={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
   "1":glyph={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
   "2":glyph={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
   "3":glyph={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
   "4":glyph={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
   "5":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
   "6":glyph={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
   "7":glyph={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
   "8":glyph={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
   "9":glyph={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
   "A":glyph={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
   "B":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
   "C":glyph={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
   "D":glyph={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
   "E":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
   "F":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
   "R":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
   "S":glyph={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
   "V":glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b00100};
   "T":glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
   ":":glyph={5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b00000};
   default:glyph=0;
  endcase end
 endfunction
 always @* begin
  character=" ";local_x=0;local_y=0;area_active=0;
  if(x>=208 && x<464 && y>=56 && y<120)begin
   area_active=1;local_x=x-208;local_y=y-56;
   case(character_cell)
    0:character="V";1:character=":";2:character="0";3:character=VERSION_DIGIT;
   endcase
  end else if(x>=144 && x<528 && y>=160 && y<224)begin
   area_active=1;local_x=x-144;local_y=y-160;
   case(character_cell)
    0:character="E";1,2:character="R";3:character=":";
    4:character=hex_char(code[7:4]);5:character=hex_char(code[3:0]);
   endcase
  end else if(code==8'h13 && x>=144 && x<528 && y>=272 && y<336)begin
   area_active=1;local_x=x-144;local_y=y-272;
   case(character_cell)
    0:character="D";1:character="A";2:character="T";3:character=":";
    4:character="0";5:character=hex_char(sd_stage);
   endcase
  end else if(code!=8'h13 && x>=176 && x<496 && y>=272 && y<336)begin
   area_active=1;local_x=x-176;local_y=y-272;
   case(character_cell)
    0:character="S";1:character="D";2:character=":";
    3:character="0";4:character=hex_char(sd_stage);
   endcase
  end else if(x>=176 && x<496 && y>=368 && y<432)begin
   area_active=1;local_x=x-176;local_y=y-368;
   case(character_cell)
    0:character="F";1:character="S";2:character=":";
    3:character=hex_char(fs_stage[7:4]);4:character=hex_char(fs_stage[3:0]);
   endcase
  end
 end
 wire [34:0] bitmap=glyph(character);
 wire [5:0] index=34-(row*6'd5+column);
 assign ink=area_active && column<5 && row<7 && bitmap[index];
endmodule

// Small live diagnostics confined to the upper black letterbox.
// F is presented frames per one pixel-clock second; U is missing lines (hex).
module status_overlay(input [9:0] x,y,input [5:0] fps,
 input [7:0] missed_lines,output ink);
 wire [9:0] lx=x-16,ly=y-8;
 wire [3:0] cell_index=lx[7:4];
 wire [2:0] col=lx[3:1],row=ly[3:1];
 reg [7:0] character;
 reg [3:0] tens,ones;
 function [7:0] hex_char;
  input [3:0] n;
  begin hex_char=n<10 ? "0"+n : "A"+n-10;end
 endfunction
 function [34:0] glyph;
  input [7:0] c;
  begin case(c)
   "0":glyph={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
   "1":glyph={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
   "2":glyph={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
   "3":glyph={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
   "4":glyph={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
   "5":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
   "6":glyph={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
   "7":glyph={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
   "8":glyph={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
   "9":glyph={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
   "A":glyph={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
   "B":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
   "C":glyph={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
   "D":glyph={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
   "E":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
   "F":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
   "U":glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
   "V":glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b00100};
   ":":glyph={5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b00000};
   default:glyph=0;
  endcase end
 endfunction
 always @* begin
  if(fps>=60)begin tens=6;ones=fps-60;end
  else if(fps>=50)begin tens=5;ones=fps-50;end
  else if(fps>=40)begin tens=4;ones=fps-40;end
  else if(fps>=30)begin tens=3;ones=fps-30;end
  else if(fps>=20)begin tens=2;ones=fps-20;end
  else if(fps>=10)begin tens=1;ones=fps-10;end
  else begin tens=0;ones=fps;end
  character=" ";
  case(cell_index)
   0:character="V";1:character=":";2:character="0";3:character="6";
   5:character="F";6:character=":";7:character=hex_char(tens);8:character=hex_char(ones);
   10:character="U";11:character=":";12:character=hex_char(missed_lines[7:4]);
   13:character=hex_char(missed_lines[3:0]);
  endcase
 end
 wire [34:0] bitmap=glyph(character);
 wire [5:0] bit_index=34-(row*6'd5+col);
 assign ink=x>=16 && x<240 && y>=8 && y<22 && col<5 && row<7 && bitmap[bit_index];
endmodule

// A: ROI area, G: global changed cells, E: rejection reason, S: stable frames.
module camera_foreground_overlay(input wire de,input wire [9:0] x,y,input wire [23:0] base_rgb,
    input wire [12:0] area,global_changed,raw_area,skin_area,core_area,input wire [2:0] rejection,input wire [3:0] stable_count,
    input wire [2:0] track_reason,input wire track_locked,current_valid,diagnostics_enabled,
    input wire [7:0] fresh_rate,update_rate,
    input wire scene_diagnostics,input wire [12:0] scene_left,scene_right,
    input wire [31:0] pipeline_rates,input wire pipeline_rates_valid,
    input wire [3:0] association_mismatch,
    output wire [23:0] rgb);
    function [14:0] glyph;
        input [4:0] n;
        begin case(n)
            0:glyph=15'b111_101_101_101_111;1:glyph=15'b010_110_010_010_111;
            2:glyph=15'b111_001_111_100_111;3:glyph=15'b111_001_111_001_111;
            4:glyph=15'b101_101_111_001_001;5:glyph=15'b111_100_111_001_111;
            6:glyph=15'b111_100_111_101_111;7:glyph=15'b111_001_001_001_001;
            8:glyph=15'b111_101_111_101_111;9:glyph=15'b111_101_111_001_111;
            10:glyph=15'b111_101_111_101_101;11:glyph=15'b100_100_111_101_111;
            12:glyph=15'b111_100_100_100_111;13:glyph=15'b001_001_111_101_111;
            14:glyph=15'b111_100_111_100_111;15:glyph=15'b111_100_111_100_100;
            16:glyph=15'b111_100_101_101_111; // G
            17:glyph=15'b111_100_111_001_111; // S
            18:glyph=15'b101_101_110_101_101; // K
            19:glyph=15'b101_101_101_101_111; // U
            20:glyph=15'b111_010_010_010_010; // T
            21:glyph=15'b100_100_100_100_111; // L
            22:glyph=15'b101_101_101_101_010; // V
            23:glyph=15'b111_101_111_100_100; // P
            24:glyph=15'b101_111_111_101_101; // M
            25:glyph=15'b110_101_110_101_101; // R
            default:glyph=0;
        endcase end
    endfunction
    reg [4:0] character;
    always @*begin
        if(y>=80)begin
            case(x[9:4])
                1:character=21;
                2:character={2'b0,scene_left[12]};3:character={1'b0,scene_left[11:8]};
                4:character={1'b0,scene_left[7:4]};5:character={1'b0,scene_left[3:0]};
                7:character=25;
                8:character={2'b0,scene_right[12]};9:character={1'b0,scene_right[11:8]};
                10:character={1'b0,scene_right[7:4]};11:character={1'b0,scene_right[3:0]};
                default:character=31;
            endcase
        end else if(y>=56)begin
            case(x[9:4])
                1:character=16;
                2:character={1'b0,pipeline_rates[31:28]};3:character={1'b0,pipeline_rates[27:24]};
                5:character=11;
                6:character={1'b0,pipeline_rates[23:20]};7:character={1'b0,pipeline_rates[19:16]};
                9:character=23;
                10:character={1'b0,pipeline_rates[15:12]};11:character={1'b0,pipeline_rates[11:8]};
                13:character=18;
                14:character={1'b0,pipeline_rates[7:4]};15:character={1'b0,pipeline_rates[3:0]};
                17:character=22;18:character={4'b0,pipeline_rates_valid};
                default:character=31;
            endcase
        end else if(y>=32)begin
            case(x[9:4])
                1:character=15;
                2:character={1'b0,fresh_rate[7:4]};3:character={1'b0,fresh_rate[3:0]};
                5:character=19;
                6:character={1'b0,update_rate[7:4]};7:character={1'b0,update_rate[3:0]};
                9:character=20;10:character={2'b0,track_reason};
                12:character=21;13:character={4'b0,track_locked};
                15:character=12;16:character={4'b0,current_valid};
                18:character=24;19:character={1'b0,association_mismatch};
                default:character=31;
            endcase
        end else case(x[9:4])
            1:character=10;2:character={2'b0,area[12]};3:character={1'b0,area[11:8]};
            4:character={1'b0,area[7:4]};5:character={1'b0,area[3:0]};
            7:character=16;8:character={2'b0,global_changed[12]};9:character={1'b0,global_changed[11:8]};
            10:character={1'b0,global_changed[7:4]};11:character={1'b0,global_changed[3:0]};
            13:character=14;14:character={2'b0,rejection};15:character=17;16:character={1'b0,stable_count};
            18:character=13;19:character={2'b0,raw_area[12]};20:character={1'b0,raw_area[11:8]};
            21:character={1'b0,raw_area[7:4]};22:character={1'b0,raw_area[3:0]};
            24:character=18;25:character={2'b0,skin_area[12]};26:character={1'b0,skin_area[11:8]};
            27:character={1'b0,skin_area[7:4]};28:character={1'b0,skin_area[3:0]};
            31:character=12;32:character={2'b0,core_area[12]};33:character={1'b0,core_area[11:8]};
            34:character={1'b0,core_area[7:4]};35:character={1'b0,core_area[3:0]};
            default:character=31;
        endcase
    end
    wire zone=x>=16 && ((x<576 && y>=8 && y<28) ||
        (diagnostics_enabled && ((x<320 && y>=32 && y<52) || (x<304 && y>=56 && y<76) ||
            (scene_diagnostics && x<192 && y>=80 && y<100))));
    wire [4:0] ty=y>=80 ? y-80 : y>=56 ? y-56 : y>=32 ? y-32 : y-8;
    wire [14:0] font=glyph(character);
    wire ink=x[3:2]<3 && font[14-(ty[4:2]*3+x[3:2])];
    assign rgb=!de ? 24'd0 : zone ? (ink ? 24'hffffff : 24'h000000) : base_rgb;
endmodule

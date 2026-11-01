// Read VIDEO.BIN in a FAT32 root directory. Follows directory and file FAT chains.
// Sector-level backpressure: once accepted, all 512 bytes must be consumed.
module museum_phase1_mount #(parameter EXPECTED_BYTES=210816000,MOUNT_ONLY=0) (
    input clk, input rst, input sd_ready, input [7:0] sd_error,
    output reg read_req, output reg [31:0] read_lba,
    input [7:0] sd_data, input sd_valid, input sd_done,
    output reg mounted, output reg [7:0] error,
    input next_sector, output sector_ready,
    output [7:0] stream_data, output stream_valid, output reg sector_done,
    output reg [31:0] file_size,output [4:0] debug_state,
    output [31:0] mount_fat_lba,mount_data_lba,mount_first_cluster,mount_max_cluster,
    output [7:0] mount_spc,output [2:0] mount_shift
);
    // Register host outputs together; its accepted latch prevents duplicate reads.
    reg sd_ready_q,sd_valid_q,sd_done_q;reg [7:0] sd_error_q,sd_data_q;
    always @(posedge clk)begin
      if(rst)begin sd_ready_q<=0;sd_valid_q<=0;sd_done_q<=0;sd_error_q<=0;sd_data_q<=0;end
      else begin
        sd_ready_q<=sd_ready;sd_valid_q<=sd_valid;sd_done_q<=sd_done;
        sd_error_q<=sd_error;sd_data_q<=sd_data;
      end
    end
    localparam WAIT_SD=0, BOOT=1, BOOT_CHECK=2, DIR=3, DIR_CHECK=4,
        FAT=5, FAT_CHECK=6, AVAILABLE=7, DATA=8, ADVANCE=9, HALT=11,
        BOOT_GEOMETRY=12, GEOMETRY_CHECK=13, DIR_START=14, GEOMETRY_SUB=15,GEOMETRY_SHIFT=16,GEOMETRY_ADD=17,DIR_SUB=18,DIR_SHIFT=19,FILE_SIZE_CHECK=20,FILE_LOW_CHECK=21,FILE_HIGH_CHECK=22,FILE_ACCEPT=23,FAT_ACCEPT=24,PARTITION_START=25,GEOMETRY_WAIT=26;
    reg [4:0] state,failure_stage;
    assign debug_state=error!=0 ? failure_stage : state;
    reg [31:0] directory_offset,directory_shifted;
    reg [31:0] geometry_overhead,geometry_amount,geometry_clusters;
    reg [9:0] byte_index;
    reg [7:0] bpb [0:63];
    reg [7:0] partition [0:63];
    reg [15:0] signature;
    reg [31:0] volume_lba, fat_lba, data_lba, fat_sectors, total_sectors;
    reg [31:0] current_cluster, first_cluster, max_cluster, next_cluster;
    reg [31:0] bytes_left;
    reg [7:0] sectors_per_cluster, sector_in_cluster,last_sector;
    reg [2:0] cluster_shift;
    reg volume_selected, directory_fat;
    reg [12:0] directory_budget;
    reg name_match, entry_valid, dir_end, found;
    reg [31:0] entry_cluster, entry_size;
    assign mount_fat_lba=fat_lba;assign mount_data_lba=data_lba;
    assign mount_first_cluster=first_cluster;assign mount_max_cluster=max_cluster;
    assign mount_spc=sectors_per_cluster;assign mount_shift=cluster_shift;
    wire [15:0] bytes_per_sector = {bpb[12],bpb[11]};
    wire [15:0] reserved = {bpb[15],bpb[14]};
    wire [31:0] bpb_fatsz = {bpb[39],bpb[38],bpb[37],bpb[36]};
    wire [31:0] bpb_total = {bpb[35],bpb[34],bpb[33],bpb[32]};
    wire [31:0] bpb_root = {4'b0,bpb[47][3:0],bpb[46],bpb[45],bpb[44]};
    wire [31:0] overhead = reserved + (bpb[16]==2 ? (bpb_fatsz<<1) : bpb_fatsz);
    wire [3:0] active_fat = bpb[40][7] ? bpb[40][3:0] : 4'd0;
    wire [8:0] fat_offset = {current_cluster[6:0],2'b00};
    assign sector_ready = (state == AVAILABLE) && !error;
    assign stream_data = sd_data_q;
    assign stream_valid = !MOUNT_ONLY && state == DATA && sd_valid_q;

    function [7:0] filename_byte;
        input [4:0] index;
        begin case (index)
            0: filename_byte="A"; 1: filename_byte="V"; 2: filename_byte="V";
            3: filename_byte="I"; 4: filename_byte="D"; 5: filename_byte="E";
            6: filename_byte="O"; 7: filename_byte=" ";
            8: filename_byte="B"; 9: filename_byte="I"; 10: filename_byte="N";
            default: filename_byte=0;
        endcase end
    endfunction
    function [2:0] log_cluster;
        input [7:0] value;
        begin case (value)
            1: log_cluster=0; 2: log_cluster=1; 4: log_cluster=2; 8: log_cluster=3;
            16: log_cluster=4; 32: log_cluster=5; 64: log_cluster=6; default: log_cluster=7;
        endcase end
    endfunction
    task sector;
        input [31:0] lba;
        input [4:0] destination;
        begin
            read_lba <= lba; read_req <= 1; byte_index <= 0;
            signature <= 0; state <= destination;
        end
    endtask
    task fail;
        input [7:0] code;
        begin failure_stage<=state;error <= code; mounted <= 0; read_req <= 0; state <= HALT; end
    endtask

    reg boot_is_fat32,boot_geometry_bad;
    // BPB bytes finish hundreds of clocks before BOOT_CHECK; register their
    // classification to shorten the state/control path without a timing exception.
    always @(posedge clk)begin
      if(rst)begin boot_is_fat32<=0;boot_geometry_bad<=1;end
      else begin boot_is_fat32<=(bytes_per_sector == 512 && bpb[17] == 0 && bpb[18] == 0 &&
                            bpb[22] == 0 && bpb[23] == 0 && bpb_fatsz != 0);boot_geometry_bad<=(bpb[13] == 0 || (bpb[13] & (bpb[13]-1'b1)) != 0 ||
                                reserved == 0 || (bpb[16]!=1 && bpb[16]!=2) || active_fat >= bpb[16] ||
                                bpb[42] != 0 || bpb[43] != 0);end
    end
    reg geometry_invalid,first_high,fat_invalid;
    always @(posedge clk)begin
      geometry_invalid<=bpb_total<=geometry_overhead || max_cluster<65527 || bpb_root<2 || bpb_root>=max_cluster;
      first_high<=first_cluster>=max_cluster;
      fat_invalid<=next_cluster<2 || next_cluster>=max_cluster || next_cluster>=32'h0ffffff0 || next_cluster==current_cluster;
    end
    integer k;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            directory_offset<=0;directory_shifted<=0;geometry_overhead<=0;geometry_amount<=0;geometry_clusters<=0;failure_stage<=0;state <= WAIT_SD; read_req <= 0; read_lba <= 0;
            byte_index <= 0; signature <= 0; mounted <= 0; error <= 0;
            volume_lba <= 0; fat_lba <= 0; data_lba <= 0; fat_sectors <= 0;
            total_sectors <= 0; current_cluster <= 0; first_cluster <= 0;
            max_cluster <= 0; next_cluster <= 0; bytes_left <= 0;
            last_sector<=0;sectors_per_cluster <= 0; sector_in_cluster <= 0; cluster_shift <= 0;
            volume_selected <= 0; directory_fat <= 0; directory_budget <= 0;
            name_match <= 0; entry_valid <= 0; dir_end <= 0; found <= 0;
            entry_cluster <= 0; entry_size <= 0; file_size <= 0; sector_done <= 0;
            for (k=0;k<64;k=k+1) begin bpb[k]<=0; partition[k]<=0; end
        end else begin
            sector_done <= 0;
            if (sd_error_q != 0) fail(8'h10 | sd_error_q);
            else begin
                if (sd_valid_q && read_req) begin
                    byte_index <= byte_index + 1'b1;
                    if (byte_index == 510) signature[7:0] <= sd_data_q;
                    if (byte_index == 511) signature[15:8] <= sd_data_q;
                    if (state == BOOT) begin
                        if (byte_index < 64) bpb[byte_index[5:0]] <= sd_data_q;
                        if (byte_index >= 446 && byte_index < 510)
                            partition[byte_index-446] <= sd_data_q;
                    end
                    if (state == DIR && !found && !dir_end) begin
                        case (byte_index[4:0])
                            0: begin
                                name_match <= sd_data_q == "A";
                                entry_valid <= sd_data_q != 0 && sd_data_q != 8'he5;
                                entry_cluster <= 0; entry_size <= 0;
                                if (sd_data_q == 0) dir_end <= 1;
                            end
                            1,2,3,4,5,6,7,8,9,10:
                                if (sd_data_q != filename_byte(byte_index[4:0])) name_match <= 0;
                            11: if (sd_data_q[4] || sd_data_q[3] || sd_data_q == 8'h0f) entry_valid <= 0;
                            20: entry_cluster[23:16] <= sd_data_q;
                            21: entry_cluster[31:24] <= {4'b0,sd_data_q[3:0]};
                            26: entry_cluster[7:0] <= sd_data_q;
                            27: entry_cluster[15:8] <= sd_data_q;
                            28: entry_size[7:0] <= sd_data_q;
                            29: entry_size[15:8] <= sd_data_q;
                            30: entry_size[23:16] <= sd_data_q;
                            31: if (name_match && entry_valid) begin
                                found <= 1; first_cluster <= entry_cluster;
                                file_size <= {sd_data_q,entry_size[23:0]};
                            end
                        endcase
                    end
                    if (state == FAT && byte_index >= fat_offset && byte_index < {1'b0,fat_offset}+4)
                        case (byte_index[1:0])
                            0: next_cluster[7:0] <= sd_data_q;
                            1: next_cluster[15:8] <= sd_data_q;
                            2: next_cluster[23:16] <= sd_data_q;
                            3: next_cluster[31:24] <= {4'b0,sd_data_q[3:0]};
                        endcase
                end
                case (state)
                    WAIT_SD: if (sd_ready_q) sector(0,BOOT);
                    BOOT: if (sd_done_q) begin read_req<=0; state<=BOOT_CHECK; end
                    BOOT_CHECK: begin
                        if (signature != 16'haa55 || byte_index != 512) fail(8'h20);
                        else if (boot_is_fat32) begin
                            if (boot_geometry_bad)
                                fail(8'h21);
                            else begin
                                fat_sectors <= bpb_fatsz; total_sectors <= bpb_total;
                                last_sector<=bpb[13]-8'd1;sectors_per_cluster <= bpb[13]; cluster_shift <= log_cluster(bpb[13]);
                                geometry_overhead<=overhead;state<=BOOT_GEOMETRY;
                            end
                        end else if (!volume_selected) begin
                            volume_selected <= 1;
                            if (partition[4] == 8'h0b || partition[4] == 8'h0c) begin
                                volume_lba <= {partition[11],partition[10],partition[9],partition[8]};
                                state<=PARTITION_START;
                            end else if (partition[20] == 8'h0b || partition[20] == 8'h0c) begin
                                volume_lba <= {partition[27],partition[26],partition[25],partition[24]};
                                state<=PARTITION_START;
                            end else if (partition[36] == 8'h0b || partition[36] == 8'h0c) begin
                                volume_lba <= {partition[43],partition[42],partition[41],partition[40]};
                                state<=PARTITION_START;
                            end else if (partition[52] == 8'h0b || partition[52] == 8'h0c) begin
                                volume_lba <= {partition[59],partition[58],partition[57],partition[56]};
                                state<=PARTITION_START;
                            end else fail(8'h22);
                        end else fail(8'h22);
                    end
                    PARTITION_START: sector(volume_lba,BOOT);
                    BOOT_GEOMETRY: begin
                        fat_lba<=volume_lba+reserved+(active_fat==1 ? bpb_fatsz : 32'd0);
                        data_lba<=volume_lba+geometry_overhead;
                        state<=GEOMETRY_SUB;
                    end
                    GEOMETRY_SUB: begin geometry_amount<=bpb_total-geometry_overhead;state<=GEOMETRY_SHIFT;end
                    GEOMETRY_SHIFT: begin geometry_clusters<=geometry_amount>>cluster_shift;state<=GEOMETRY_ADD;end
                    GEOMETRY_ADD: begin max_cluster<=geometry_clusters+2;state<=GEOMETRY_WAIT;end
                    GEOMETRY_WAIT: state<=GEOMETRY_CHECK;
                    GEOMETRY_CHECK: begin
                        if (geometry_invalid)
                            fail(8'h21);
                        else begin
                            current_cluster<=bpb_root; sector_in_cluster<=0;
                            found<=0; dir_end<=0; state<=DIR_SUB;
                        end
                    end
                    DIR_SUB: begin directory_offset<=current_cluster-2;state<=DIR_SHIFT;end
                    DIR_SHIFT: begin directory_shifted<=directory_offset<<cluster_shift;state<=DIR_START;end
                    DIR_START: sector(data_lba+directory_shifted,DIR);
                    DIR: if (sd_done_q) begin read_req<=0; state<=DIR_CHECK; end
                    DIR_CHECK: begin
                        if (byte_index != 512) fail(8'h23);
                        else if (found) begin
                            state<=FILE_SIZE_CHECK;
                        end else if (dir_end || directory_budget == 4095) fail(8'h25);
                        else begin
                            directory_budget <= directory_budget+1'b1;
                            if (sector_in_cluster != last_sector) begin
                                sector_in_cluster<=sector_in_cluster+1'b1;
                                sector(read_lba+1,DIR);
                            end else begin
                                directory_fat<=1; next_cluster<=0;
                                sector(fat_lba+(current_cluster >> 7),FAT);
                            end
                        end
                    end
                    FILE_SIZE_CHECK: if(file_size!=EXPECTED_BYTES)fail(8'h24);else state<=FILE_LOW_CHECK;
                    FILE_LOW_CHECK: if(first_cluster<2)fail(8'h24);else state<=FILE_HIGH_CHECK;
                    FILE_HIGH_CHECK: if(first_high)fail(8'h24);else state<=FILE_ACCEPT;
                    FILE_ACCEPT: begin mounted<=1;current_cluster<=first_cluster;bytes_left<=file_size;sector_in_cluster<=0;state<=AVAILABLE;end
                    FAT: if (sd_done_q) begin read_req<=0; state<=FAT_CHECK; end
                    FAT_CHECK: begin
                        if (byte_index != 512 || fat_invalid)
                            fail(directory_fat ? 8'h25 : 8'h26);
                        else state<=FAT_ACCEPT;
                    end
                    FAT_ACCEPT: begin
                        current_cluster<=next_cluster;sector_in_cluster<=0;
                        if(directory_fat)state<=DIR_SUB;else state<=AVAILABLE;
                    end
                    AVAILABLE: if (!MOUNT_ONLY && next_sector) sector(data_lba+((current_cluster-2)<<cluster_shift)+sector_in_cluster,DATA);
                    DATA: if (!MOUNT_ONLY && sd_done_q) begin
                        read_req<=0; sector_done<=1; state<=ADVANCE;
                    end
                    ADVANCE: if(MOUNT_ONLY)state<=HALT;else begin
                        if (byte_index != 512) fail(8'h23);
                        else if (bytes_left == 512) begin
                            bytes_left<=file_size; current_cluster<=first_cluster;
                            sector_in_cluster<=0; state<=AVAILABLE;
                        end else begin
                            bytes_left<=bytes_left-512;
                            if (sector_in_cluster != last_sector) begin
                                sector_in_cluster<=sector_in_cluster+1'b1; state<=AVAILABLE;
                            end else begin
                                directory_fat<=0; next_cluster<=0;
                                sector(fat_lba+(current_cluster >> 7),FAT);
                            end
                        end
                    end
                    HALT: read_req<=0;
                endcase
            end
        end
    end
endmodule

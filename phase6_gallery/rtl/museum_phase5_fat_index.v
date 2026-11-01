// museum_phase6_fat_index: mount a FAT32 volume and index the 8.3 BMP files in its root
// directory. Reference implementation only -- it reads through the client side of
// museum_phase2_sd_sector and never touches the physical SD layer or the SDRAM.
//
// Supports an MBR-partitioned FAT32 volume (partition types 0x0B/0x0C) and a
// superfloppy whose boot sector is sector 0. Long-file-name entries, directories,
// volume labels, dot entries and deleted entries are recognised and skipped rather
// than counted. The index holds up to MAX_ENTRIES BMP files; further entries are
// ignored and `count` saturates there.
//
// FAT32 directory entries are 4-byte aligned and 512 is a multiple of 4, so a
// 4-byte FAT entry never straddles a sector boundary.
module museum_phase6_fat_index #(
    parameter integer MAX_ENTRIES = 29,
    parameter CACHE_AUDIO = 0
) (
    input wire [1:0] audio_raddr,
    output wire [3:0] audio_present,
    output wire [31:0] audio_cluster,audio_size,
    input  wire        clk,
    input  wire        rst,
    input  wire        scan_start,
    output reg  [15:0] count,
    output reg         done,
    output reg         busy,
    output reg  [7:0]  error,
    input  wire [4:0]  ent_raddr,
    output wire [31:0] ent_cluster,
    output wire [31:0] ent_size,
    output wire [95:0] ent_name,
    // volume geometry, valid once done is high (used by the file loader)
    output wire [31:0] geo_fat_lba,
    output wire [31:0] geo_data_lba,
    output wire [7:0]  geo_spc,
    output wire [2:0]  geo_shift,
    output wire [31:0] geo_max_cluster,
    output reg         sec_req,
    output reg  [31:0] sec_lba,
    input  wire        sec_ready,
    input  wire        sec_valid,
    input  wire        sec_error,
    output reg  [8:0]  buf_addr,
    input  wire [7:0]  buf_data,
    output reg         sec_release
);
    localparam [4:0] IDLE = 5'd0, RD_BOOT = 5'd1, COPY_BOOT = 5'd2, COPY_PART = 5'd3,
                     CHK_BOOT = 5'd4, PART_SCAN = 5'd5, RD_BPB = 5'd6, COPY_BPB = 5'd7,
                     CHK_BPB = 5'd8, CHK_GEOM = 5'd9, DIR_START = 5'd10, NEXT_SEC = 5'd11,
                     RD_DIR = 5'd12, ENT_COPY = 5'd13, ENT_PROC = 5'd14,
                     NEXT_SEC_ADV = 5'd15, RD_FAT = 5'd16, FAT_WAIT = 5'd17,
                     FAT_COPY = 5'd18, FAT_CHK = 5'd19, FINISH = 5'd20, HALT = 5'd21,
                     COPY_SIG = 5'd22, RELEASE = 5'd23, GEOM_WAIT0=5'd24, GEOM_WAIT1=5'd25, GEOM_WAIT2=5'd26, DIR_PRIME=5'd27,GEOM_WAIT3=5'd28,PART_PRIME=5'd29,DIR_ADDR_WAIT0=5'd30,DIR_ADDR_WAIT1=5'd31;

    localparam [7:0] E_SD    = 8'h10,   // block service reported an error
                     E_BOOT  = 8'h20,   // bad boot-sector signature
                     E_BPB   = 8'h21,   // unusable FAT32 BPB or geometry
                     E_PART  = 8'h22,   // no FAT32 partition found
                     E_CHAIN = 8'h24;   // invalid cluster chain

    reg [4:0]  state;
    reg [7:0]  bpb [0:63];
    reg [6:0] i;
    // Register byte enables before the BPB register bank to shorten the
    // 100MHz address-decode fanout. Geometry only consumes bytes <=47 after
    // the copy phase, by which time their queued writes have committed.
    reg [7:0] bpb_data_q;
    always @(posedge clk)bpb_data_q<=buf_data;
    genvar bi;
    generate for(bi=0;bi<64;bi=bi+1)begin: bpb_copy_pipeline
        localparam [5:0] PHASE=bi+2;
        reg write_byte;
        always @(posedge clk)begin
            if(rst)write_byte<=0;
            else write_byte<=(state==COPY_BOOT || state==COPY_BPB) && i>1 && i[5:0]==PHASE;
            if(!rst && write_byte)bpb[bi]<=bpb_data_q;
        end
    end endgenerate
    // Only FAT32 type and starting LBA are consumed from each MBR slot.
    // Keep all four slots and the original two-cycle sector-buffer timing.
    reg [7:0] part_type[0:3];
    reg [31:0] part_lba[0:3];
    genvar pi;
    generate for(pi=0;pi<4;pi=pi+1)begin: partition_fields
        always @(posedge clk)if(!rst && state==COPY_PART)begin
            if(i==pi*16+6) part_type[pi]<=buf_data;
            if(i==pi*16+10) part_lba[pi][7:0]<=buf_data;
            if(i==pi*16+11) part_lba[pi][15:8]<=buf_data;
            if(i==pi*16+12) part_lba[pi][23:16]<=buf_data;
            if(i==pi*16+13) part_lba[pi][31:24]<=buf_data;
        end
    end endgenerate
    reg [7:0]  ent [0:31];
    generate if(CACHE_AUDIO)begin: audio_cache
        reg [3:0] present;
        reg [31:0] clusters[0:3],sizes[0:3];
        wire [1:0] slot=ent[7]-8'd49;
        wire audio_name_ok=ent[0]=="A" && ent[1]=="U" && ent[2]=="D" &&
          ent[3]=="0" && ent[4]=="0" && ent[5]=="0" && ent[6]=="0" &&
          ent[7]>="1" && ent[7]<="4" &&
          (ent[8]=="W" || ent[8]=="w") &&
          (ent[9]=="A" || ent[9]=="a") &&
          (ent[10]=="V" || ent[10]=="v");
        assign audio_present=present;
        assign audio_cluster=clusters[audio_raddr];
        assign audio_size=sizes[audio_raddr];
        always @(posedge clk)begin
            if(rst || (state==IDLE && scan_start))present<=0;
            else if(state==ENT_PROC && audio_name_ok && ent[11]!=8'h0f &&
                (ent[11]&8'h18)==0 && !present[slot])begin
                clusters[slot]<={ent[21][3:0],ent[20],ent[27],ent[26]};
                sizes[slot]<={ent[31],ent[30],ent[29],ent[28]};
                present[slot]<=1;
            end
        end
    end else begin: no_audio_cache
        assign audio_present=0;assign audio_cluster=0;assign audio_size=0;
    end endgenerate
    reg [7:0]  fatb[0:3];
    reg [31:0] volume_lba, fat_lba, data_lba, total_sectors, max_cluster;
    reg [31:0] root_cluster, cur_cluster;
    reg [31:0] overhead;
    reg [15:0] entry_count;reg [28:0] present;
    wire name_ok_next=ent[0]=="I" && ent[1]=="M" && ent[2]=="G" &&
      ent[3]=="0" && ent[4]=="0" && ent[5]=="0" &&
      ent[6]>="0" && ent[6]<="2" && ent[7]>="0" && ent[7]<="9" &&
      (ent[6]!="0" || ent[7]!="0") && (ent[6]!="2" || ent[7]<="9");
    wire [5:0] named_number=(ent[6]-8'd48)*6'd10+(ent[7]-8'd48);
    // Name bytes 0..7 settle long before ENT_PROC (entry copy finishes at byte31).
    // Register the arithmetic slot and format check before the indexed present lookup.
    reg name_ok;
    reg [4:0] named_slot;
    always @(posedge clk)begin
      name_ok<=name_ok_next;
      named_slot<=named_number-6'd1;
    end
    reg [7:0]  spc, sec_in_cluster;
    reg [7:0]  sig_lo, sig_hi;
    reg [2:0]  cluster_shift;
    reg [8:0] ent_off;
    reg [4:0]  ent_idx;
    reg        dir_end;

    reg [31:0] idx_cluster [0:MAX_ENTRIES-1];
    reg [31:0] idx_size    [0:MAX_ENTRIES-1];
    reg [95:0] idx_name    [0:MAX_ENTRIES-1];

    assign ent_cluster = idx_cluster[ent_raddr];
    assign ent_size    = idx_size[ent_raddr];
    assign ent_name    = idx_name[ent_raddr];
    assign geo_fat_lba = fat_lba;
    assign geo_data_lba= data_lba;
    assign geo_spc     = spc;
    assign geo_shift   = cluster_shift;
    assign geo_max_cluster = max_cluster;

    wire [15:0] bps      = {bpb[12], bpb[11]};
    wire [15:0] reserved = {bpb[15], bpb[14]};
    wire [31:0] bpbfatsz = {bpb[39], bpb[38], bpb[37], bpb[36]};
    wire [31:0] bpftotal = {bpb[35], bpb[34], bpb[33], bpb[32]};
    wire [31:0] bpbroot  = {4'b0, bpb[47][3:0], bpb[46], bpb[45], bpb[44]};
    wire [31:0] ovh      = reserved + (bpb[16] == 8'd2 ? (bpbfatsz << 1) : bpbfatsz);
    reg [31:0] geom_free,geom_shifted,geom_cl;
    reg bad_bpb,geometry_invalid,cluster_invalid;
    reg [31:0] overhead_q,partition_lba_q;
    reg partition_type_ok;
    always @(posedge clk)begin
      overhead_q<=ovh;
      geometry_invalid<=total_sectors<=overhead || geom_cl<32'd65527 || root_cluster<32'd2 || root_cluster>=geom_cl;
      cluster_invalid<=cur_cluster<32'd2 || cur_cluster>=max_cluster || cur_cluster>=32'h0ffffff0;
      partition_type_ok<=part_type[i[5:4]]==8'h0b || part_type[i[5:4]]==8'h0c;
      partition_lba_q<=part_lba[i[5:4]];
    end
    always @(posedge clk)bad_bpb<=(bps != 16'd512 || bpb[13] == 8'd0 ||
                        (bpb[13] & (bpb[13] - 8'd1)) != 8'd0 ||
                        (bpb[16] != 8'd1 && bpb[16] != 8'd2) || reserved == 16'd0 ||
                        bpbfatsz == 32'd0 || bpb[42] != 8'd0 || bpb[43] != 8'd0);

    always @(posedge clk)begin geom_free<=total_sectors-overhead;geom_shifted<=geom_free>>cluster_shift;geom_cl<=geom_shifted+32'd2;end
    reg [31:0] cur_lba,cur_delta,cur_shifted;
    always @(posedge clk)begin
      cur_delta<=cur_cluster-32'd2;cur_shifted<=cur_delta<<cluster_shift;
      cur_lba<=data_lba+cur_shifted;
    end
    wire [31:0] fat_off  = cur_cluster << 2;
    wire [31:0] fatpos   = fat_off & 32'h1ff;
    wire [31:0] fat_next = {4'b0, fatb[3][3:0], fatb[2], fatb[1], fatb[0]};

    function [2:0] log2spc;
        input [7:0] v;
        begin
            case (v)
                8'd1:    log2spc = 3'd0; 8'd2:   log2spc = 3'd1;
                8'd4:    log2spc = 3'd2; 8'd8:   log2spc = 3'd3;
                8'd16:   log2spc = 3'd4; 8'd32:  log2spc = 3'd5;
                8'd64:   log2spc = 3'd6; 8'd128: log2spc = 3'd7;
                default: log2spc = 3'd7;
            endcase
        end
    endfunction

    task fail;
        input [7:0] code;
        begin
            error       <= code;
            busy        <= 1'b0;
            done        <= 1'b0;
            sec_req     <= 1'b0;
            sec_release <= 1'b1;
            state       <= RELEASE;
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE; count <= 16'd0; done <= 1'b0; busy <= 1'b0; error <= 8'd0;
            sec_req <= 1'b0; sec_lba <= 32'd0; sec_release <= 1'b0; buf_addr <= 9'd0;
            volume_lba <= 0; fat_lba <= 0; data_lba <= 0; total_sectors <= 0;
            max_cluster <= 0; root_cluster <= 0; cur_cluster <= 0;
            overhead <= 0; entry_count <= 0;present<=0;
            spc <= 0; sec_in_cluster <= 0; cluster_shift <= 0; sig_lo <= 0; sig_hi <= 0;
            i <= 0; ent_off <= 0; ent_idx <= 0; dir_end <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (scan_start) begin
                        count       <= 16'd0;
                        entry_count <= 16'd0;present<=0;
                        error       <= 8'd0;
                        done        <= 1'b0;
                        busy        <= 1'b1;
                        sec_lba     <= 32'd0;
                        sec_req     <= 1'b1;
                        state       <= RD_BOOT;
                    end
                end

                // ---- sector 0: MBR partition table or superfloppy BPB ------------
                RD_BOOT: if (sec_error) fail(E_SD);
                else if (sec_valid) begin
                    sec_req  <= 1'b0;
                    buf_addr <= 9'd0;
                    i        <= 9'd0;
                    state    <= COPY_BOOT;
                end

                COPY_BOOT: begin
                    if (i < 9'd64) buf_addr <= i;
                    if (i == 9'd65) begin
                        i     <= 9'd0;
                        state <= COPY_SIG;
                    end else begin
                        i <= i + 9'd1;
                    end
                end

                // capture the 0x55AA signature from bytes 510-511
                COPY_SIG: begin
                    if (i < 9'd2) buf_addr <= 9'd510 + i;
                    if (i == 9'd2) sig_lo <= buf_data;
                    if (i == 9'd3) begin
                        sig_hi <= buf_data;
                        i      <= 9'd0;
                        state  <= COPY_PART;
                    end else begin
                        i <= i + 9'd1;
                    end
                end

                COPY_PART: begin
                    if (i < 9'd64) buf_addr <= 9'd446 + i;

                    if (i == 9'd65) begin
                        sec_release <= 1'b1;
                        state       <= CHK_BOOT;
                    end else begin
                        i <= i + 9'd1;
                    end
                end

                CHK_BOOT: begin
                    sec_release <= 1'b0;
                    if (sig_lo != 8'h55 || sig_hi != 8'haa) begin
                        fail(E_BOOT);
                    end else if (bps == 16'd512 && bpb[17] == 8'd0 && bpb[18] == 8'd0 &&
                                 bpb[22] == 8'd0 && bpb[23] == 8'd0 && bpbfatsz != 32'd0) begin
                        // sector 0 is itself the volume boot record (superfloppy)
                        volume_lba    <= 32'd0;
                        total_sectors <= bpftotal;
                        root_cluster  <= bpbroot;
                        overhead      <= overhead_q;
                        state         <= CHK_BPB;
                    end else begin
                        i     <= 9'd0;
                        state <= PART_PRIME;
                    end
                end

                // ---- look for a FAT32 partition entry ----------------------------
                PART_PRIME: state<=PART_SCAN;
                PART_SCAN: begin
                    if (partition_type_ok) begin
                        volume_lba <= partition_lba_q;
                        sec_lba    <= partition_lba_q;
                        sec_req    <= 1'b1;
                        state      <= RD_BPB;
                    end else if (i >= 9'd48) begin
                        fail(E_PART);
                    end else begin
                        i <= i + 9'd16;state<=PART_PRIME;
                    end
                end

                RD_BPB: if (sec_error) fail(E_SD);
                else if (sec_valid) begin
                    sec_req  <= 1'b0;
                    buf_addr <= 9'd0;
                    i        <= 9'd0;
                    state    <= COPY_BPB;
                end

                COPY_BPB: begin
                    if (i < 9'd64) buf_addr <= i;
                    if (i == 9'd65) begin
                        sec_release <= 1'b1;
                        state       <= CHK_BPB;
                    end else begin
                        i <= i + 9'd1;
                    end
                end

                // ---- validate the BPB, then the derived geometry -----------------
                CHK_BPB: begin
                    sec_release <= 1'b0;
                    if (bad_bpb) begin
                        fail(E_BPB);
                    end else begin
                        total_sectors <= bpftotal;
                        root_cluster  <= bpbroot;
                        overhead      <= overhead_q;
                        spc           <= bpb[13];
                        cluster_shift <= log2spc(bpb[13]);
                        state         <= GEOM_WAIT0;
                    end
                end

                GEOM_WAIT0: state<=GEOM_WAIT1;
                GEOM_WAIT1: state<=GEOM_WAIT2;
                GEOM_WAIT2: state<=GEOM_WAIT3;
                GEOM_WAIT3: state<=CHK_GEOM;
                CHK_GEOM: begin
                    if (geometry_invalid) begin
                        fail(E_BPB);
                    end else begin
                        max_cluster <= geom_cl;
                        state       <= DIR_START;
                    end
                end

                // ---- walk the root directory -------------------------------------
                DIR_START: begin
                    fat_lba        <= volume_lba + reserved;
                    data_lba       <= volume_lba + overhead;
                    cur_cluster    <= root_cluster;
                    sec_in_cluster <= 8'd0;
                    dir_end        <= 1'b0;
                    state          <= DIR_PRIME;
                end

                DIR_PRIME: state<=DIR_ADDR_WAIT0;
                DIR_ADDR_WAIT0: state<=DIR_ADDR_WAIT1;
                DIR_ADDR_WAIT1: state<=NEXT_SEC;
                NEXT_SEC: begin
                    sec_release <= 1'b0;
                    if (cluster_invalid) begin
                        fail(E_CHAIN);
                    end else begin
                        sec_lba <= cur_lba + {23'd0, sec_in_cluster};
                        sec_req <= 1'b1;
                        state   <= RD_DIR;
                    end
                end

                RD_DIR: if (sec_error) fail(E_SD);
                else if (sec_valid) begin
                    sec_req  <= 1'b0;
                    ent_idx  <= 5'd0;
                    ent_off  <= 9'd0;
                    i        <= 9'd0;
                    state    <= ENT_COPY;
                end

                ENT_COPY: begin
                    if (i < 9'd32) buf_addr <= ent_off + i;
                    if (i > 9'd1) ent[i[5:0] - 6'd2] <= buf_data;
                    if (i == 9'd33) begin
                        i     <= 9'd0;
                        state <= ENT_PROC;
                    end else begin
                        i <= i + 9'd1;
                    end
                end

                ENT_PROC: begin
                    if (ent[0] == 8'h00) begin
                        // end-of-directory marker
                        dir_end     <= 1'b1;
                        sec_release <= 1'b1;
                        state       <= NEXT_SEC_ADV;
                    end else begin
                        if (ent[0] != 8'he5 && ent[11] != 8'h0f &&
                            (ent[11] & 8'h08) == 8'd0 && (ent[11] & 8'h10) == 8'd0 &&
                            ent[0] != 8'h2e &&
                            (ent[10] == 8'h50 || ent[10] == 8'h70) &&
                            (ent[9]  == 8'h4d || ent[9]  == 8'h6d) &&
                            (ent[8]  == 8'h42 || ent[8]  == 8'h62) &&
                            entry_count < MAX_ENTRIES && name_ok && !present[named_slot]) begin
                            idx_cluster[named_slot] <=
                                {ent[21][3:0], ent[20], ent[27], ent[26]};
                            idx_size[named_slot] <=
                                {ent[31], ent[30], ent[29], ent[28]};
                            idx_name[named_slot] <=
                                {ent[10], ent[9], ent[8], ent[7], ent[6], ent[5],
                                 ent[4], ent[3], ent[2], ent[1], ent[0], 8'h00};
                            entry_count <= entry_count + 16'd1;present[named_slot]<=1;
                        end
                        if (ent_idx == 5'd15) begin
                            sec_release <= 1'b1;
                            state       <= NEXT_SEC_ADV;
                        end else begin
                            ent_idx <= ent_idx + 5'd1;
                            ent_off <= ent_off + 9'd32;
                            state   <= ENT_COPY;
                        end
                    end
                end

                NEXT_SEC_ADV: begin
                    sec_release <= 1'b0;
                    if (dir_end) begin
                        count <= entry_count;
                        error <= present==29'h1fffffff ? 8'd0 : 8'h25;
                        done  <= present==29'h1fffffff;
                        busy  <= 1'b0;
                        state <= FINISH;
                    end else if (sec_in_cluster + 8'd1 < spc) begin
                        sec_in_cluster <= sec_in_cluster + 8'd1;
                        state          <= DIR_PRIME;
                    end else begin
                        state <= RD_FAT;
                    end
                end

                // ---- follow the root-directory cluster chain ---------------------
                RD_FAT: begin
                    sec_lba <= fat_lba + (fat_off >> 9);
                    sec_req <= 1'b1;
                    i       <= 9'd0;
                    state   <= FAT_WAIT;
                end

                FAT_WAIT: if (sec_error) fail(E_SD);
                else if (sec_valid) begin
                    sec_req <= 1'b0;
                    state   <= FAT_COPY;
                end

                FAT_COPY: begin
                    if (i < 9'd4) buf_addr <= fatpos[8:0] + i;
                    if (i > 9'd1) fatb[i[1:0] - 2'd2] <= buf_data;
                    if (i == 9'd5) state <= FAT_CHK;
                    else           i     <= i + 9'd1;
                end

                FAT_CHK: begin
                    sec_release <= 1'b1;
                    if (fat_next >= 32'h0ffffff8) begin
                        // end-of-chain marker: the directory really is complete
                        count <= entry_count;
                        error <= present==29'h1fffffff ? 8'd0 : 8'h25;
                        done  <= present==29'h1fffffff;
                        busy  <= 1'b0;
                        state <= FINISH;
                    end else if (fat_next < 32'd2 || fat_next >= max_cluster ||
                                 fat_next == cur_cluster) begin
                        // free entry, out of range, or a loop: report the corruption
                        // instead of passing a truncated directory off as complete
                        fail(E_CHAIN);
                    end else begin
                        cur_cluster    <= fat_next;
                        sec_in_cluster <= 8'd0;
                        state          <= DIR_PRIME;
                    end
                end

                FINISH: begin
                    sec_release <= 1'b0;
                    sec_req     <= 1'b0;
                    state       <= IDLE;
                end

                HALT: begin
                    sec_req     <= 1'b0;
                    sec_release <= 1'b0;
                    state       <= IDLE;
                end

                // Hold the reader's release until it is idle again, so a faulted
                // scan cannot leave a sector locked and wedge the next request.
                RELEASE: begin
                    sec_req     <= 1'b0;
                    sec_release <= 1'b1;
                    if (sec_ready) begin
                        sec_release <= 1'b0;
                        state       <= IDLE;
                    end
                end

                default: state <= HALT;
            endcase
        end
    end
endmodule

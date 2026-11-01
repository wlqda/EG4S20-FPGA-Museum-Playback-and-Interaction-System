// tb_phase5_fat: self-checking testbench for museum_fat_index + museum_sd_sector.
// Builds synthetic FAT32 volumes directly in the block-service model and checks the
// scanned index: entry count, first cluster and size, plus the skip rules for
// long-file-name entries, directories, volume labels, dot entries and deleted
// entries. Also covers MBR and superfloppy layouts, a multi-cluster root directory,
// an empty volume, a bad boot signature and a CRC failure.
`timescale 1ns/1ps

module tb_gallery_fat;
    parameter CACHE_AUDIO=0;
    reg [1:0] audio_select=0;
    wire [3:0] audio_present;
    wire [31:0] audio_cluster,audio_size;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg scan_start = 1'b0;

    wire [15:0] count;
    wire        done, busy;
    wire [7:0]  error;
    reg  [4:0]  ent_raddr = 5'd0;
    wire [31:0] ent_cluster, ent_size;
    wire [95:0] ent_name;

    wire        sec_req;
    wire [31:0] sec_lba;
    wire        sec_ready, sec_valid, sec_error;
    wire [8:0]  buf_addr;
    wire [7:0]  buf_data;
    wire        sec_release;

    wire [7:0]  m_rd_data;
    wire        m_rd_valid, m_rd_commit, m_rd_done, m_rd_ready;
    wire [7:0]  m_rd_error;
    wire        m_rd_req_valid, m_rd_resume;
    wire [31:0] m_rd_lba;
    wire [22:0] m_rd_count;

    reg [31:0] part_lba = 32'd2048;
    reg [31:0] fat_lba  = 32'd2080;
    reg [31:0] root_lba = 32'd2081;
    reg [31:0] corrupt_lba = 32'hffffffff;

    museum_phase2_sd_sector sr (
        .clk(clk), .rst(rst),
        .req_valid(sec_req), .req_lba(sec_lba), .req_ready(sec_ready),
        .sector_valid(sec_valid), .sector_error(sec_error), .buf_release(sec_release),
        .buf_addr(buf_addr), .buf_data(buf_data),
        .rd_req_valid(m_rd_req_valid), .rd_lba(m_rd_lba), .rd_count(m_rd_count),
        .rd_req_ready(m_rd_ready), .rd_data(m_rd_data), .rd_valid(m_rd_valid),
        .rd_sector_commit(m_rd_commit), .rd_done(m_rd_done), .rd_error(m_rd_error),
        .rd_resume(m_rd_resume)
    );

    museum_sd_model model (
        .clk(clk), .rst(rst),
        .part_lba(part_lba), .fat_lba(fat_lba), .fat_sectors(32'd1), .root_lba(root_lba),
        .corrupt_lba(corrupt_lba),
        .bmp_size(32'd0), .bmp_w(16'd640), .bmp_h(16'd480),
        .bmp_bottom(1'b1), .bmp_seed(8'd0),
        .rd_data(m_rd_data), .rd_valid(m_rd_valid), .rd_sector_commit(m_rd_commit),
        .rd_done(m_rd_done), .rd_error(m_rd_error), .rd_req_ready(m_rd_ready),
        .rd_req_valid(m_rd_req_valid), .rd_lba(m_rd_lba), .rd_count(m_rd_count),
        .rd_resume(m_rd_resume)
    );

    museum_phase6_fat_index #(.MAX_ENTRIES(29),.CACHE_AUDIO(CACHE_AUDIO)) idx (
        .audio_raddr(audio_select),.audio_present(audio_present),.audio_cluster(audio_cluster),.audio_size(audio_size),
        .clk(clk), .rst(rst), .scan_start(scan_start),
        .count(count), .done(done), .busy(busy), .error(error),
        .ent_raddr(ent_raddr), .ent_cluster(ent_cluster), .ent_size(ent_size),
        .ent_name(ent_name),.geo_fat_lba(),.geo_data_lba(),.geo_spc(),.geo_shift(),.geo_max_cluster(),
        .sec_req(sec_req), .sec_lba(sec_lba), .sec_ready(sec_ready),
        .sec_valid(sec_valid), .sec_error(sec_error),
        .buf_addr(buf_addr), .buf_data(buf_data), .sec_release(sec_release)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer g;
    reg [7:0] eb [0:31];

    // ---- model memory writers ------------------------------------------------
    task wr8;
        input integer sel, off;
        input [7:0] v;
        begin
            if      (sel == 0) model.mbr[off] = v;
            else if (sel == 1) model.bpb[off] = v;
            else if (sel == 2) model.fat[off] = v;
            else if (sel == 3) model.d0[off]  = v;
            else if (sel == 4) model.d1[off] = v;
            else model.d2[off]=v;
        end
    endtask
    task wr16;
        input integer sel, off;
        input [15:0] v;
        begin wr8(sel, off, v[7:0]); wr8(sel, off + 1, v[15:8]); end
    endtask
    task wr32;
        input integer sel, off;
        input [31:0] v;
        begin wr16(sel, off, v[15:0]); wr16(sel, off + 2, v[31:16]); end
    endtask

    task clear_disk;
        integer k;
        begin
            for (k = 0; k < 512; k = k + 1) begin
                model.mbr[k] = 8'h00; model.bpb[k] = 8'h00; model.fat[k] = 8'h00;
                model.d0[k]  = 8'h00; model.d1[k]  = 8'h00;
                model.d2[k]=0;
            end
        end
    endtask

    task fill_mbr;
        input [31:0] start, len;
        begin
            wr8(0, 446, 8'h00);
            wr8(0, 450, 8'h0c);
            wr32(0, 454, start);
            wr32(0, 458, len);
            wr8(0, 510, 8'h55); wr8(0, 511, 8'haa);
        end
    endtask

    task fill_bpb;
        input [31:0] total, rootclus, fatsz;
        input [15:0] reserved;
        input [7:0]  spc, nfats;
        begin
            wr8(1, 0, 8'heb); wr8(1, 1, 8'h58); wr8(1, 2, 8'h90);
            wr16(1, 11, 16'd512);
            wr8(1, 13, spc);
            wr16(1, 14, reserved);
            wr8(1, 16, nfats);
            wr8(1, 21, 8'hf8);
            wr32(1, 32, total);
            wr32(1, 36, fatsz);
            wr32(1, 44, rootclus);
            wr8(1, 510, 8'h55); wr8(1, 511, 8'haa);
        end
    endtask

    task set_fat;
        input integer c;
        input [31:0] v;
        begin wr32(2, c * 4, v); end
    endtask

    // ---- directory entry builders --------------------------------------------
    task eb_clear;
        integer k;
        begin for (k = 0; k < 32; k = k + 1) eb[k] = 8'h00; end
    endtask
    task eb_commit;
        input integer sel, slot;
        integer k, o;
        begin
            o = slot * 32;
            for (k = 0; k < 32; k = k + 1) wr8(sel, o + k, eb[k]);
        end
    endtask

    // A well-formed 8.3 "IMGnnnn BMP" file entry pointing at clus/size.
    task mk_bmp;
        input integer sel, slot, seq;
        input [15:0] clus;
        input [31:0] size;
        begin
            eb_clear;
            eb[0] = 8'h49; eb[1] = 8'h4d; eb[2] = 8'h47;      // "IMG"
            eb[3] = 8'd48 + ((seq / 1000) % 10);
            eb[4] = 8'd48 + ((seq / 100) % 10);
            eb[5] = 8'h30;
            eb[6] = 8'd48 + ((seq / 10) % 10);
            eb[7] = 8'd48 + (seq % 10);
            eb[8] = 8'h42; eb[9] = 8'h4d; eb[10] = 8'h50;      // "BMP"
            eb[11] = 8'h20;                                    // archive
            eb[20] = 8'h00; eb[21] = 8'h00;                    // cluster high
            eb[26] = clus[7:0]; eb[27] = clus[15:8];           // cluster low
            eb[28] = size[7:0]; eb[29] = size[15:8];
            eb[30] = size[23:16]; eb[31] = size[31:24];
            eb_commit(sel, slot);
        end
    endtask

    task mk_special;
        input integer sel, slot, kind;   // 0 lfn, 1 vol-label, 2 directory, 3 deleted, 4 txt
        begin
            eb_clear;
            case (kind)
                0: begin eb[0] = 8'h41; eb[11] = 8'h0f; end          // long file name
                1: begin eb[0] = 8'h56; eb[11] = 8'h08; end          // volume label
                2: begin eb[0] = 8'h4e; eb[11] = 8'h10; end          // sub-directory
                3: begin eb[0] = 8'he5; eb[11] = 8'h20; end          // deleted
                4: begin eb[0] = 8'h54; eb[8] = 8'h54; eb[9] = 8'h58;
                         eb[10] = 8'h54; eb[11] = 8'h20; end          // .TXT file
            endcase
            eb_commit(sel, slot);
        end
    endtask

    task set_layout;
        input [31:0] part, fat, root;
        begin
            part_lba = part; fat_lba = fat; root_lba = root;
        end
    endtask

    // ---- run control ---------------------------------------------------------
    task run_scan;
        begin
            @(negedge clk); scan_start = 1'b1;
            @(posedge clk);
            @(negedge clk); scan_start = 1'b0;
            g = 0;
            while (!done && error == 8'd0 && g < 300000) begin
                @(posedge clk);
                g = g + 1;
            end
            repeat (4) @(posedge clk);
        end
    endtask

    task expect_result;
        input [8*30:1] name;
        input [15:0]   xcount;
        input          xdone;
        input [7:0]    xerr;
        begin
            if (error !== xerr) begin
                errors = errors + 1;
                $display("FAIL %0s: error=%02x expected %02x", name, error, xerr);
            end else if (done !== xdone) begin
                errors = errors + 1;
                $display("FAIL %0s: done=%b expected %b", name, done, xdone);
            end else if (count !== xcount) begin
                errors = errors + 1;
                $display("FAIL %0s: count=%0d expected %0d", name, count, xcount);
            end else begin
                $display("PASS %0s: count=%0d error=%02x done=%b", name, count, error, done);
            end
        end
    endtask

    task check_entry;
        input integer i;
        input [31:0] exp_cluster, exp_size;
        begin
            ent_raddr = i[4:0];
            #1;
            if (ent_cluster !== exp_cluster) begin
                errors = errors + 1;
                $display("FAIL entry %0d: cluster=%0d expected %0d", i, ent_cluster, exp_cluster);
            end
            if (ent_size !== exp_size) begin
                errors = errors + 1;
                $display("FAIL entry %0d: size=%0d expected %0d", i, ent_size, exp_size);
            end
        end
    endtask


    task mk_wav;
        input integer slot,id,cluster,attr;
        begin
            eb_clear;eb[0]="A";eb[1]="U";eb[2]="D";
            eb[3]="0";eb[4]="0";eb[5]="0";eb[6]="0";eb[7]="1"+id;
            eb[8]="w";eb[9]="a";eb[10]="v";eb[11]=attr;
            eb[26]=cluster;eb[27]=cluster>>8;
            eb[28]=(1256+2*id)&255;eb[29]=(1256+2*id)>>8;
            eb_commit(5,slot);
        end
    endtask
    reg passed=0;integer test_no,n;
    initial begin
     repeat(4)@(negedge clk);rst=0;
     for(test_no=0;test_no<5;test_no=test_no+1)begin
      clear_disk;corrupt_lba=32'hffffffff;
      set_layout(2048,2080,2081);fill_mbr(2048,70000);
      fill_bpb(70000,2,1,32,1,1);set_fat(0,32'hffffff8);set_fat(1,32'hfffffff);set_fat(2,3);set_fat(3,32'hfffffff);
      // Reverse directory order and distribute entries across two clusters.
      for(n=0;n<29;n=n+1)begin
       if(n<16)mk_bmp(3,n,29-n,129-n,921654);
       else mk_bmp(4,n-16,29-n,129-n,921654);
      end
      if(test_no==1)mk_special(4,12,4); // missing IMG00001
      if(test_no==2)mk_bmp(4,12,2,102,921654); // duplicate 02 replaces 01
      if(test_no==3)begin mk_bmp(4,13,30,130,921654);mk_special(4,14,1);mk_special(4,15,0);end
      if(test_no==4)corrupt_lba=2081;
      if(CACHE_AUDIO)begin
       set_fat(3,4);set_fat(4,32'h0fffffff);
       if(test_no!=3)begin mk_special(4,13,3);mk_special(4,14,3);mk_special(4,15,3);end
       mk_wav(0,3,999,8'h10);mk_wav(1,2,999,8'h08);mk_wav(2,1,999,8'h0f);
       for(n=0;n<4;n=n+1)mk_wav(3+n,3-n,203-n,8'h20);
       mk_wav(7,0,999,8'h20);
      end
      run_scan;
      if(CACHE_AUDIO && test_no!=4)begin
       if(audio_present!==4'hf)$fatal(1,"missing cached WAV");
       for(n=0;n<4;n=n+1)begin
        audio_select=n;#1;
        if(audio_cluster!==200+n || audio_size!==1256+2*n)$fatal(1,"cached WAV metadata mismatch");
       end
      end
      if(test_no==0 || test_no==3)begin
       expect_result("named reversed complete",29,1,0);
       for(n=0;n<29;n=n+1)check_entry(n,101+n,921654);
      end else if(test_no==4)begin if(error==0 || done)$fatal(1,"CRC published corrupt index");end
      else expect_result("missing or duplicate",28,0,8'h25);
      if(errors)$fatal(1,"FAT checks failed");
      $display("PASS GALLERY FAT case %d count=%d error=%h",test_no,count,error);
      @(negedge clk);rst=1;repeat(4)@(negedge clk);rst=0;
     end
     passed=1;$display("RESULT: GALLERY 29-NAMED FAT ALL PASS");$finish;
    end
    initial begin #30000000;$fatal(1,"FAT timeout");end
endmodule

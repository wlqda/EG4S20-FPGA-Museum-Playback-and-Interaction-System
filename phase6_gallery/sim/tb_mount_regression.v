`timescale 1ns/1ps
module tb_mount_regression;
 reg passed=0;
 parameter SUPERFLOPPY=0,ACTIVE_FAT=0,BROKEN=0,NATIVE=0,MOUNT_ONLY=0;
 reg clk=0,rst=1;always #5 clk=~clk;
 wire mounted,prepared,fs_req,ext_req;
 wire [31:0] fs_lba,ext_lba,fat_lba,data_lba,first_cluster,max_cluster,size;
 wire [7:0] spc,fs_error,ext_error;
 wire [2:0] shift;
 wire [22:0] ext_count;
 reg [7:0] mock_data=0;reg mock_valid=0,mock_done=0;
 wire [7:0] native_data,native_error;wire native_valid,native_done,native_ready;
 wire [7:0] data=NATIVE ? native_data : mock_data;
 wire valid=NATIVE ? native_valid : mock_valid;
 wire done=NATIVE ? native_done : mock_done;
 wire [7:0] stream;wire stream_valid;
 wire req=mounted ? ext_req : fs_req;
 wire [31:0] lba=mounted ? ext_lba : fs_lba;
 wire [22:0] count=mounted ? ext_count : 23'd1;
 reg [31:0] lbas[0:31];reg [7:0] disk[0:16383];
 museum_phase1_mount #(.EXPECTED_BYTES(3072),.MOUNT_ONLY(MOUNT_ONLY)) fs(.clk(clk),.rst(rst),.sd_ready(NATIVE ? native_ready : 1'b1),
  .sd_error(8'd0),.read_req(fs_req),.read_lba(fs_lba),.sd_data(data),
  .sd_valid(!mounted && valid),.sd_done(!mounted && done),.mounted(mounted),
  .error(fs_error),.debug_state(),.next_sector(1'b0),.sector_ready(),.stream_data(),.stream_valid(),
  .sector_done(),.file_size(size),.mount_fat_lba(fat_lba),.mount_data_lba(data_lba),
  .mount_first_cluster(first_cluster),.mount_max_cluster(max_cluster),
  .mount_spc(spc),.mount_shift(shift));
 fat32_extents #(.FILE_SECTORS(6)) ext(.clk(clk),.rst(rst),.mounted(mounted),
  .fat_lba(fat_lba),.data_lba(data_lba),.first_cluster(first_cluster),
  .max_cluster(max_cluster),.spc(spc),.cluster_shift(shift),
  .read_req(ext_req),.read_lba(ext_lba),.read_count(ext_count),
  .data(data),.valid(mounted && valid),.done(mounted && done),.resume_ok(1'b1),
  .stream_valid(stream_valid),.stream_data(stream),.prepared(prepared),.error(ext_error));
 wire card_clk;tri1 card_cmd;tri1 [3:0] card_dat;
 wire card_rdreq;wire [39:0] card_addr;reg [15:0] card_data=0;
 museum_phase1_sdio_host #(.SIMULATION(1)) host(.clk(clk),.rst(rst),.SD_CLK(card_clk),
  .SD_CMD(card_cmd),.SD_DAT(card_dat),.read_req(req && NATIVE),.read_lba(lba),
  .read_count(count),.resume_ok(1'b1),.ready(native_ready),.data(native_data),
  .valid(native_valid),.done(native_done),.block_valid(),.error(native_error),.debug_state());
 sd_fake card(.rstn_async(!rst),.sdclk(card_clk),.sdcmd(card_cmd),.sddat(card_dat),
  .rdreq(card_rdreq),.rdaddr(card_addr),.rddata(card_data),.show_status_bits(),
  .show_sdcmd_en(),.show_sdcmd_cmd(),.show_sdcmd_arg());
 integer ci,co;
 always @(posedge card_clk)if(card_rdreq && NATIVE)begin
  co=-1;
  for(ci=0;ci<32;ci=ci+1)if(lbas[ci]==card_addr[39:8])co=ci*512+card_addr[7:0]*2;
  card_data<=co<0 ? 16'hffff : {disk[co+1],disk[co]};
 end
 integer i,j,offset,n,k,got=0,runs=0;
 reg [31:0] actual;
 initial begin
  $readmemh("../sim/mount_fixtures/test_lbas.hex",lbas);$readmemh("../sim/mount_fixtures/test_disk.hex",disk);
  if(ACTIVE_FAT)begin
   for(i=0;i<32;i=i+1)begin
    if(lbas[i]==2048)disk[i*512+40]=8'h81;
    if(lbas[i]==2080)lbas[i]=3104;
   end
  end
  if(BROKEN)for(i=0;i<32;i=i+1)if(lbas[i]==(ACTIVE_FAT ? 3104 : 2080))disk[i*512+40*4]=20;
  #100;@(negedge clk)rst=0;
  if(!NATIVE)forever begin
   wait(req);actual=lba;n=count;
   if(prepared)begin
    if(runs%2==0 && (actual!=4164-(SUPERFLOPPY ? 2048 : 0) || n!=4))$fatal(1,"First extent incorrect %d %d",actual,n);
    if(runs%2==1 && (actual!=4204-(SUPERFLOPPY ? 2048 : 0) || n!=2))$fatal(1,"Second extent incorrect");
    runs=runs+1;
   end
   for(k=0;k<n;k=k+1)begin
    offset=-1;
    for(i=0;i<32;i=i+1)if(lbas[i]==(SUPERFLOPPY ? actual+k+2048 : actual+k))offset=i*512;
    if(offset<0)$fatal(1,"Unknown sector %d",actual+k);
    for(j=0;j<512;j=j+1)begin
     @(negedge clk);mock_valid=1;mock_data=disk[offset+j];
     @(negedge clk);mock_valid=0;repeat((j%3))@(negedge clk);
    end
   end
   @(negedge clk);mock_done=1;@(negedge clk);mock_done=0;wait(!req);
  end
 end
 always @(posedge clk)begin
  if(!rst && NATIVE && native_error!=0)$fatal(1,"Native SD error %h",native_error);
  if(!rst && fs_error!=0)$fatal(1,"Mount error %h",fs_error);
  if(BROKEN && ext_error==8'h33)begin passed=1;$display("PASS FAT_BROKEN");$finish;end
  if(!BROKEN && ext_error!=0)$fatal(1,"Extent error %h",ext_error);
  if(stream_valid)begin
   if(stream!==8'(((got%3072)*17+31)&255))$fatal(1,"File byte %d incorrect %h",got,stream);
   got=got+1;
   if(got==6144)begin passed=1;$display("PASS FAT: %d bytes; fragmented root/file and EOF loop",got);$finish;end
  end
 end
 // Allow for the probe's fourfold reduction from the original 50-MHz card clock.
 initial begin #(NATIVE ? 8000000 : 2000000);$fatal(1,"FAT timeout %d %d",fs.state,ext.state);end
endmodule

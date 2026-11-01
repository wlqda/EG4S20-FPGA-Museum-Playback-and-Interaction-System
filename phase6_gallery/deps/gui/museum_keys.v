// museum_keys.v
// 低有效按键 KEY2/KEY3/KEY4 的同步、消抖、短按与长按事件生成。
//
// 事件编码与 INTERFACES_V1.md 第 2 节一致（单周期脉冲）：
//   events[0] 下一项 / 下一张
//   events[1] 上一项
//   events[2] 确认
//   events[3] 返回
//   events[4] 向上（预留）
//   events[5] 向下（预留）
//   events[6..7] 保留
//
// KEY2 -> 下一项，KEY3 -> 上一项，KEY4 短按 -> 确认，KEY4 长按 -> 返回。
// 长按触发后，该次按键释放不再产生确认事件。
// 复位期间已按住的按键在复位释放后只作为基线，不产生任何事件。
// KEY1 由顶层直接接复位，不进入本模块。
//
// 消抖与长按时长通过时钟计数实现，不产生按键慢时钟。

`ifndef MUSEUM_KEYS_V
`define MUSEUM_KEYS_V

module museum_key_channel #(
  parameter integer DEBOUNCE_CYCLES   = 500000,   // 20 ms @ 25 MHz
  parameter integer LONG_PRESS_CYCLES = 15000000  // 600 ms @ 25 MHz
) (
  input  wire clk,
  input  wire rst,          // 高有效同步复位
  input  wire key_n,        // 低有效按键输入
  output reg  press,        // 短按：释放时给出单周期脉冲（按住期间未到长按时长）
  output reg  hold          // 长按：按住达到 LONG_PRESS_CYCLES 时给出单周期脉冲
);
  localparam integer CNT_W = 25;  // 600 ms @ 25 MHz = 15e6 < 2^24

  localparam [CNT_W-1:0] DB = DEBOUNCE_CYCLES[CNT_W-1:0];
  localparam [CNT_W-1:0] LP = LONG_PRESS_CYCLES[CNT_W-1:0];

  wire pressed = ~key_n;          // 按下 = 1，便于统一处理
  wire pin;

  reg [1:0]       sync_q;
  reg             stable;         // 消抖后的按下状态
  reg [CNT_W-1:0] db_cnt;
  reg [CNT_W-1:0] hold_cnt;
  reg             hold_fired;     // 本次按下已经发过长按
  reg             locked;         // 复位后已完成基线采样

  assign pin = sync_q[0];

  always @(posedge clk) begin
    if (rst) begin
      sync_q     <= {pressed, pressed};
      stable     <= 1'b0;
      db_cnt     <= {CNT_W{1'b0}};
      hold_cnt   <= {CNT_W{1'b0}};
      hold_fired <= 1'b0;
      locked     <= 1'b0;
      press      <= 1'b0;
      hold       <= 1'b0;
    end else begin
      press  <= 1'b0;
      hold   <= 1'b0;
      sync_q <= {sync_q[0], pressed};

      if (!locked) begin
        // 复位后第一次采样：以当前电平为基线，已按住的键不产生事件
        stable     <= pin;
        hold_fired <= pin;
        db_cnt     <= {CNT_W{1'b0}};
        hold_cnt   <= {CNT_W{1'b0}};
        locked     <= 1'b1;
      end else if (pin != stable) begin
        if (db_cnt == DB - 1'b1) begin
          db_cnt <= {CNT_W{1'b0}};
          stable <= pin;
          if (pin) begin
            hold_cnt   <= {CNT_W{1'b0}};
            hold_fired <= 1'b0;
          end else begin
            if (!hold_fired)
              press <= 1'b1;
          end
        end else begin
          db_cnt <= db_cnt + 1'b1;
        end
      end else begin
        db_cnt <= {CNT_W{1'b0}};
        if (stable && !hold_fired) begin
          if (hold_cnt == LP - 1'b1) begin
            hold_cnt   <= {CNT_W{1'b0}};
            hold_fired <= 1'b1;
            hold       <= 1'b1;
          end else begin
            hold_cnt <= hold_cnt + 1'b1;
          end
        end
      end
    end
  end
endmodule

module museum_keys #(
  parameter integer DEBOUNCE_CYCLES   = 500000,
  parameter integer LONG_PRESS_CYCLES = 15000000
) (
  input  wire       pixel_clk,
  input  wire       pixel_rst,
  input  wire [2:0] keys_n,     // {KEY4,KEY3,KEY2}，低有效
  output wire [7:0] events
);
  wire k2_press, k2_hold;
  wire k3_press, k3_hold;
  wire k4_press, k4_hold;

  museum_key_channel #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES), .LONG_PRESS_CYCLES(LONG_PRESS_CYCLES))
  u_key2 (.clk(pixel_clk), .rst(pixel_rst), .key_n(keys_n[0]), .press(k2_press), .hold(k2_hold));

  museum_key_channel #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES), .LONG_PRESS_CYCLES(LONG_PRESS_CYCLES))
  u_key3 (.clk(pixel_clk), .rst(pixel_rst), .key_n(keys_n[1]), .press(k3_press), .hold(k3_hold));

  museum_key_channel #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES), .LONG_PRESS_CYCLES(LONG_PRESS_CYCLES))
  u_key4 (.clk(pixel_clk), .rst(pixel_rst), .key_n(keys_n[2]), .press(k4_press), .hold(k4_hold));

  // KEY2 下一项、KEY3 上一项、KEY4 短按确认、KEY4 长按返回。
  assign events = {2'b00, k4_hold, k4_press, k3_press, k2_press};
endmodule

`endif

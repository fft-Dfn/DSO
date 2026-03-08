module sample_controller #(
    parameter DATA_W       = 8,           // 数据位宽
    parameter ADDR_W       = 10,          // 存储深度 (1024点)
    parameter AUTO_TIMEOUT = 50_000_000   // 自动触发超时阈值
)(
    input  wire              clk,
    input  wire              rst_n,

    // ================= 信号输入与路由配置 =================
    input  wire [DATA_W-1:0] in_a, in_b, in_c, in_d, in_e,
    input  wire [2:0]        sel_trig,    
    input  wire [2:0]        sel_ch1,     
    input  wire [2:0]        sel_ch2,     
    input  wire [2:0]        sel_ch3,     
    input  wire [2:0]        sel_ch4,     

    // ================= 触发与采样率配置 =================
    input  wire              trig_mode,   // 0: Normal, 1: Auto
    input  wire              trig_edge,   // 0: 上升沿, 1: 下降沿
    input  wire [DATA_W-1:0] trig_level,  
    input  wire [31:0]       sample_div,  

    // ================= 系统控制接口 =================
    input  wire              rearm,         
    output reg               capture_done,  

    // ================= BRAM 四通道写入接口 =================
    output reg               ram_we,        
    output reg  [ADDR_W-1:0] ram_waddr,     
    output reg  [DATA_W-1:0] ram_wdata_ch1, 
    output reg  [DATA_W-1:0] ram_wdata_ch2, 
    output reg  [DATA_W-1:0] ram_wdata_ch3, 
    output reg  [DATA_W-1:0] ram_wdata_ch4  
);

    // -------------------------------------------------------------------------
    // 1.动态路由选择函数 (Crossbar)
    // -------------------------------------------------------------------------
    function [DATA_W-1:0] mux_5to1;
        input [2:0]        sel;
        input [DATA_W-1:0] a, b, c, d, e;
        begin
            case (sel)
                3'd0: mux_5to1 = a;
                3'd1: mux_5to1 = b;
                3'd2: mux_5to1 = c;
                3'd3: mux_5to1 = d;
                3'd4: mux_5to1 = e;
                default: mux_5to1 = {DATA_W{1'b0}};
            endcase
        end
    endfunction

    wire [DATA_W-1:0] trig_sig = mux_5to1(sel_trig, in_a, in_b, in_c, in_d, in_e);
    wire [DATA_W-1:0] ch1_sig  = mux_5to1(sel_ch1,  in_a, in_b, in_c, in_d, in_e);
    wire [DATA_W-1:0] ch2_sig  = mux_5to1(sel_ch2,  in_a, in_b, in_c, in_d, in_e);
    wire [DATA_W-1:0] ch3_sig  = mux_5to1(sel_ch3,  in_a, in_b, in_c, in_d, in_e);
    wire [DATA_W-1:0] ch4_sig  = mux_5to1(sel_ch4,  in_a, in_b, in_c, in_d, in_e);

    // -------------------------------------------------------------------------
    // 2.采样率发生器
    // -------------------------------------------------------------------------
    reg [31:0] div_cnt;
    reg        sample_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        div_cnt     <= 32'd0;
        sample_tick <= 1'b0;
        end else if (sample_div <= 1) begin
        div_cnt     <= 32'd0;
        sample_tick <= 1'b1;
        end else if (div_cnt == sample_div - 1) begin
        div_cnt     <= 32'd0;
        sample_tick <= 1'b1;
        end else begin
        div_cnt     <= div_cnt + 1'b1;
        sample_tick <= 1'b0;
        end
  end
    // -------------------------------------------------------------------------
    // 3.数据降采样同步与边沿检测 (Critical Fix)
    // -------------------------------------------------------------------------
    // 必须确保触发判定与实际存入 RAM 的数据严格对齐
    reg [DATA_W-1:0] trig_cur, trig_last;
    reg [DATA_W-1:0] ch1_cur, ch2_cur, ch3_cur, ch4_cur;
    reg              tick_d1; // 延迟一拍的 tick，用于标示新数据已准备好

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trig_cur  <= {DATA_W{1'b0}};
            trig_last <= {DATA_W{1'b0}};
            ch1_cur   <= {DATA_W{1'b0}};
            ch2_cur   <= {DATA_W{1'b0}};
            ch3_cur   <= {DATA_W{1'b0}};
            ch4_cur   <= {DATA_W{1'b0}};
            tick_d1   <= 1'b0;
        end else begin
            tick_d1 <= sample_tick;
            if (sample_tick) begin
                trig_cur  <= trig_sig;
                trig_last <= trig_cur; // 保存降采样后的上一个历史值
                ch1_cur   <= ch1_sig;
                ch2_cur   <= ch2_sig;
                ch3_cur   <= ch3_sig;
                ch4_cur   <= ch4_sig;
            end
        end
    end

    // 边沿判定仅针对降采样后的安全数据
    wire is_rising  = (trig_last < trig_level) && (trig_cur >= trig_level);
    wire is_falling = (trig_last > trig_level) && (trig_cur <= trig_level);
    // 仅在新数据准备好的当前周期产生单脉冲触发信号
    wire edge_fired = ((trig_edge == 1'b0) ? is_rising : is_falling) && tick_d1;

    // 自动模式模式看门狗计数器
    reg [31:0] auto_cnt;
    wire force_trig = (trig_mode == 1'b1) && (auto_cnt >= AUTO_TIMEOUT);

    // -------------------------------------------------------------------------
    // 4.主控状态机与 RAM 写入数据流 (合并为纯净的单 Always 块结构)
    // -------------------------------------------------------------------------
    localparam S_IDLE      = 2'd0;
    localparam S_WAIT_TRIG = 2'd1;
    localparam S_CAPTURE   = 2'd2;
    localparam S_DONE      = 2'd3;

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            auto_cnt      <= 32'd0;
            ram_we        <= 1'b0;
            ram_waddr     <= {ADDR_W{1'b0}};
            ram_wdata_ch1 <= {DATA_W{1'b0}};
            ram_wdata_ch2 <= {DATA_W{1'b0}};
            ram_wdata_ch3 <= {DATA_W{1'b0}};
            ram_wdata_ch4 <= {DATA_W{1'b0}};
            capture_done  <= 1'b0;
        end else begin
            ram_we       <= 1'b0; // 默认产生单脉冲写使能
            capture_done <= 1'b0; // 默认拉低，用于给 Ping-Pong 缓冲产生翻转脉冲

            case (state)
                S_IDLE: begin
                    ram_waddr <= {ADDR_W{1'b0}};
                    if (rearm) state <= S_WAIT_TRIG;
                end
                
                S_WAIT_TRIG: begin
                    ram_waddr <= {ADDR_W{1'b0}};
                    if (trig_mode == 1'b1) auto_cnt <= auto_cnt + 1'b1;
                    else auto_cnt <= 32'd0;

                    // 强制触发也必须与降采样节拍 (tick_d1)对齐，保证数据阵列的完整性
                    if (edge_fired || (force_trig && tick_d1)) begin
                        state <= S_CAPTURE;
                        auto_cnt <= 32'd0;
                        
                        // 触发条件满足，立刻写入坐标原点的数据
                        ram_we        <= 1'b1;
                        ram_waddr     <= {ADDR_W{1'b0}};
                        ram_wdata_ch1 <= ch1_cur;
                        ram_wdata_ch2 <= ch2_cur;
                        ram_wdata_ch3 <= ch3_cur;
                        ram_wdata_ch4 <= ch4_cur;
                    end
                end
                
                S_CAPTURE: begin
                    // 仅在新的降采样数据点到来时执行地址推进和写入
                    if (tick_d1) begin
                        ram_we        <= 1'b1;
                        ram_waddr     <= ram_waddr + 1'b1;
                        ram_wdata_ch1 <= ch1_cur;
                        ram_wdata_ch2 <= ch2_cur;
                        ram_wdata_ch3 <= ch3_cur;
                        ram_wdata_ch4 <= ch4_cur;

                        // 边界检测：判断是否到达最大深度 (1024) 
                        if (ram_waddr == {ADDR_W{1'b1}} - 1'b1) begin
                            state <= S_DONE;
                        end
                    end
                end
                
                S_DONE: begin
                    capture_done <= 1'b1;
                    if (rearm) state <= S_WAIT_TRIG;
                end
            endcase
        end
    end

endmodule
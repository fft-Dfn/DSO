module vga_timing (
    input  wire        clk_25m,    // 必须是 25MHz 像素时钟
    input  wire        rst_n,

    // --- VGA 物理接口 ---
    output reg         vga_hs,     // 行同步
    output reg         vga_vs,     // 场同步
    output wire        vga_blank,  // 消隐信号 (1: 非显示区, 0: 显示区)

    // --- 坐标输出 (用于渲染引擎) ---
    output wire [9:0]  curr_x,     // 当前扫描到的 X 坐标 (0-639)
    output wire [9:0]  curr_y      // 当前扫描到的 Y 坐标 (0-479)
);

    // =========================================================================
    // 1. 水平 (Horizontal) 参数定义
    // =========================================================================
    localparam H_ACTIVE = 10'd640;
    localparam H_FP     = 10'd16;
    localparam H_SYNC   = 10'd96;
    localparam H_BP     = 10'd48;
    localparam H_TOTAL  = 10'd800;

    // =========================================================================
    // 2. 垂直 (Vertical) 参数定义
    // =========================================================================
    localparam V_ACTIVE = 10'd480;
    localparam V_FP     = 10'd10;
    localparam V_SYNC   = 10'd2;
    localparam V_BP     = 10'd33;
    localparam V_TOTAL  = 10'd525;

    // =========================================================================
    // 3. 行列计数器逻辑
    // =========================================================================
    reg [9:0] h_cnt;
    reg [9:0] v_cnt;

    // 行计数器：0 -> 799
    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n)
            h_cnt <= 10'd0;
        else if (h_cnt == H_TOTAL - 1'b1)
            h_cnt <= 10'd0;
        else
            h_cnt <= h_cnt + 1'b1;
    end

    // 场计数器：每跑完一行，加 1
    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n)
            v_cnt <= 10'd0;
        else if (h_cnt == H_TOTAL - 1'b1) begin
            if (v_cnt == V_TOTAL - 1'b1)
                v_cnt <= 10'd0;
            else
                v_cnt <= v_cnt + 1'b1;
        end
    end

    // =========================================================================
    // 4. 同步信号产生 (Sync Pulse)
    // 根据标准，640x480 的 HS 和 VS 均为负脉冲有效
    // =========================================================================
    always @(posedge clk_25m) begin
        vga_hs <= ~((h_cnt >= (H_ACTIVE + H_FP)) && (h_cnt < (H_ACTIVE + H_FP + H_SYNC)));
        vga_vs <= ~((v_cnt >= (V_ACTIVE + V_FP)) && (v_cnt < (V_ACTIVE + V_FP + V_SYNC)));
    end

    // =========================================================================
    // 5. 渲染接口逻辑
    // =========================================================================
    // 判定当前是否在 640x480 的有效显示区域内
    assign vga_blank = !((h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE));

    // 输出相对坐标 (仅在有效区内有效，消隐区时数值无意义)
    assign curr_x = (h_cnt < H_ACTIVE) ? h_cnt : 10'd0;
    assign curr_y = (v_cnt < V_ACTIVE) ? v_cnt : 10'd0;

endmodule
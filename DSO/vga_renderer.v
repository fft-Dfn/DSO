module vga_renderer (
    input  wire        clk_25m,
    input  wire        rst_n,

    // --- 来自 vga_timing 的原始时序与坐标 ---
    input  wire        vga_hs_in,
    input  wire        vga_vs_in,
    input  wire        vga_blank_in,
    input  wire [9:0]  curr_x,
    input  wire [9:0]  curr_y,

    // --- 来自 hmi_controller 的 UI 状态 ---
    input  wire [3:0]  ui_page,
    input  wire [3:0]  ui_cursor,
    input  wire [2:0]  view_ch_sel,
    // (此处省略触发参数的具体文本映射接口，留至字库模块处理)

    // --- 波形 BRAM 读取接口 ---
    output reg  [9:0]  wave_raddr,
    input  wire [7:0]  wave_rdata,

    // --- 字库 ROM 读取接口 (外部例化 8x16 ASCII ROM) ---
    output reg  [11:0] char_rom_addr, // 假设 256个字符 * 16行 = 4096 深度
    input  wire [7:0]  char_rom_data,

    // --- 最终输出至 VGA DAC 的信号 (已补偿延迟) ---
    output reg         vga_hs_out,
    output reg         vga_vs_out,
    output reg         vga_blank_out,
    output reg  [7:0]  vga_r,
    output reg  [7:0]  vga_g,
    output reg  [7:0]  vga_b
);

    // =========================================================================
    // Stage 1: 区域划分与地址生成 (无延迟)
    // 根据当前坐标 (curr_x, curr_y)，计算下一步需要从 RAM/ROM 哪里取数据
    // =========================================================================
    
    // 物理区域划分参数
    localparam UI_WIDTH = 10'd160;

    wire is_ui_area   = (curr_x < UI_WIDTH);
    wire is_wave_area = (curr_x >= UI_WIDTH);

    // --- 波形读取地址映射 ---
    // 右侧 480 个像素的宽度直接映射到 BRAM 的 0~479 地址
    always @(*) begin
        if (is_wave_area)
            wave_raddr = curr_x - UI_WIDTH;
        else
            wave_raddr = 10'd0;
    end

    // --- UI 文本地址映射 (简化逻辑，实际需配合字符 Tilemap) ---
    wire [6:0] char_ascii; // 当前坐标对应的 ASCII 码 (需由另一个子模块提供)
    assign char_ascii = 7'd65; // 占位符：固定显示 'A'，后续需接字符阵列逻辑

    always @(*) begin
        if (is_ui_area)
            // 字符 ASCII 码 * 16 + 当前扫描的行偏移(0-15)
            char_rom_addr = {char_ascii, curr_y[3:0]}; 
        else
            char_rom_addr = 12'd0;
    end

    // =========================================================================
    // Stage 2: 存储器读取与同步信号打拍 (延迟 1 拍)
    // =========================================================================
    
    reg        hs_d1, vs_d1, blank_d1;
    reg        is_ui_d1, is_wave_d1;
    reg [9:0]  curr_x_d1, curr_y_d1;

    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n) begin
            hs_d1      <= 1'b0;
            vs_d1      <= 1'b0;
            blank_d1   <= 1'b1;
            is_ui_d1   <= 1'b0;
            is_wave_d1 <= 1'b0;
        end else begin
            hs_d1      <= vga_hs_in;
            vs_d1      <= vga_vs_in;
            blank_d1   <= vga_blank_in;
            is_ui_d1   <= is_ui_area;
            is_wave_d1 <= is_wave_area;
            curr_x_d1  <= curr_x;
            curr_y_d1  <= curr_y;
        end
    end

    // =========================================================================
    // Stage 3: 像素混合与最终输出 (延迟 2 拍)
    // 此时 wave_rdata 和 char_rom_data 已经准备就绪
    // =========================================================================
    
    // 波形绘制逻辑：计算 BRAM 中的幅度值是否等于当前扫描的 Y 坐标
    // 波形数据为 0-255，为了在 480 高度居中，需进行偏移转换。
    // VGA 的 Y=0 在屏幕最顶端，因此需要用减法反转 Y 轴。
    wire [9:0] target_y = 10'd360 - wave_rdata; 
    
    // 给波形增加线宽 (±1像素) 以保证视觉清晰度
    wire draw_wave = is_wave_d1 && (curr_y_d1 == target_y || curr_y_d1 == target_y + 1'b1 || curr_y_d1 == target_y - 1'b1);

    // 文本绘制逻辑：判断字库点阵当前位是否为 1
    // curr_x_d1[2:0] 提取 0-7，7-x 是因为字库通常是从左到右排列高位到低位
    wire draw_text = is_ui_d1 && char_rom_data[3'd7 - curr_x_d1[2:0]];

    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n) begin
            vga_hs_out    <= 1'b0;
            vga_vs_out    <= 1'b0;
            vga_blank_out <= 1'b1;
            vga_r         <= 8'd0;
            vga_g         <= 8'd0;
            vga_b         <= 8'd0;
        end else begin
            // 同步信号再次打拍，对齐数据
            vga_hs_out    <= hs_d1;
            vga_vs_out    <= vs_d1;
            vga_blank_out <= blank_d1;

            if (blank_d1) begin
                // 消隐区必须输出黑色
                vga_r <= 8'd0;
                vga_g <= 8'd0;
                vga_b <= 8'd0;
            end else if (draw_text) begin
                // UI 文本颜色：高亮白
                vga_r <= 8'hFF; vga_g <= 8'hFF; vga_b <= 8'hFF;
            end else if (is_ui_d1) begin
                // UI 背景色：深灰
                vga_r <= 8'h20; vga_g <= 8'h20; vga_b <= 8'h20;
            end else if (draw_wave) begin
                // 波形颜色：荧光绿
                vga_r <= 8'h00; vga_g <= 8'hFF; vga_b <= 8'h00;
            end else begin
                // 波形区背景：纯黑，带网格线
                if (curr_x_d1[4:0] == 5'd0 || curr_y_d1[4:0] == 5'd0) begin
                    vga_r <= 8'h10; vga_g <= 8'h10; vga_b <= 8'h10; // 暗色网格
                end else begin
                    vga_r <= 8'h00; vga_g <= 8'h00; vga_b <= 8'h00;
                end
            end
        end
    end

endmodule
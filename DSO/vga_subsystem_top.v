module vga_subsystem_top (
    input  wire        clk_25m,       // 必须为 25MHz 像素时钟
    input  wire        rst_n,

    // --- 来自主控状态机 (hmi_controller) 的 UI 状态 ---
    input  wire [3:0]  ui_page,
    input  wire [3:0]  ui_cursor,
    input  wire [2:0]  view_ch_sel,

    // --- 与波形 BRAM (pingpong_bram_buffer) 的接口 ---
    output wire [9:0]  wave_raddr,
    input  wire [7:0]  wave_rdata,

    // --- 物理 VGA DAC 输出 ---
    output wire        vga_hs,
    output wire        vga_vs,
    output wire        vga_blank,
    output wire [7:0]  vga_r,
    output wire [7:0]  vga_g,
    output wire [7:0]  vga_b
);

    // =========================================================================
    // 内部连线声明 (Internal Nets)
    // =========================================================================
    wire        hs_raw;
    wire        vs_raw;
    wire        blank_raw;
    wire [9:0]  curr_x;
    wire [9:0]  curr_y;

    wire [6:0]  char_ascii;
    wire        is_cursor;

    wire [11:0] char_rom_addr;
    wire [7:0]  char_rom_data;

    // =========================================================================
    // 1. VGA 时序基准产生
    // =========================================================================
    vga_timing u_vga_timing (
        .clk_25m    (clk_25m),
        .rst_n      (rst_n),
        .vga_hs     (hs_raw),
        .vga_vs     (vs_raw),
        .vga_blank  (blank_raw),
        .curr_x     (curr_x),
        .curr_y     (curr_y)
    );

    // =========================================================================
    // 2. OSD 字符映射表 (将物理坐标与 UI 状态转化为 ASCII 码)
    // =========================================================================
    osd_tilemap u_osd_tilemap (
        .curr_x     (curr_x),
        .curr_y     (curr_y),
        .ui_page    (ui_page),
        .ui_cursor  (ui_cursor),
        .char_ascii (char_ascii),
        .is_cursor  (is_cursor)
    );

    // =========================================================================
    // 3. ASCII 字库 ROM (固化硬件结构)
    // 深度: 4096 (128字符 * 16行), 宽度: 8位
    // =========================================================================
    // 此处要求你必须在工程目录下提供一份名为 "ascii_8x16.hex" 的字库文件
    (* rom_style = "block" *) reg [7:0] ascii_rom_mem [0:4095];

    initial begin
        $readmemh("ascii_8x16.hex", ascii_rom_mem);
    end

    // ROM 同步读取逻辑 (延迟 1 拍)
    reg [7:0] char_rom_data_reg;
    always @(posedge clk_25m) begin
        char_rom_data_reg <= ascii_rom_mem[char_rom_addr];
    end
    assign char_rom_data = char_rom_data_reg;

    // =========================================================================
    // 4. VGA 混合渲染引擎 (处理时序对齐与颜色输出)
    // =========================================================================
    vga_renderer u_vga_renderer (
        .clk_25m       (clk_25m),
        .rst_n         (rst_n),

        // 原始时序输入
        .vga_hs_in     (hs_raw),
        .vga_vs_in     (vs_raw),
        .vga_blank_in  (blank_raw),
        .curr_x        (curr_x),
        .curr_y        (curr_y),

        // 交互状态输入
        .ui_page       (ui_page),
        .ui_cursor     (ui_cursor),
        .view_ch_sel   (view_ch_sel),
        .char_ascii    (char_ascii), 
        .is_cursor     (is_cursor),  // 注意：此处已根据之前讨论补齐端口

        // 存储器接口
        .wave_raddr    (wave_raddr),
        .wave_rdata    (wave_rdata),
        .char_rom_addr (char_rom_addr),
        .char_rom_data (char_rom_data),

        // 最终延时对齐后的物理输出
        .vga_hs_out    (vga_hs),
        .vga_vs_out    (vga_vs),
        .vga_blank_out (vga_blank),
        .vga_r         (vga_r),
        .vga_g         (vga_g),
        .vga_b         (vga_b)
    );

endmodule
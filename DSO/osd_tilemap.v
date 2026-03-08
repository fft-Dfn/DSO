module osd_tilemap (
    input  wire [9:0] curr_x,      // 来自 VGA 时序的当前 X 坐标
    input  wire [9:0] curr_y,      // 来自 VGA 时序的当前 Y 坐标
    input  wire [3:0] ui_page,     // 来自主控的状态：当前页面
    input  wire [3:0] ui_cursor,   // 来自主控的状态：当前光标索引
    
    output reg  [6:0] char_ascii,  // 输出给渲染器的 ASCII 码
    output wire       is_cursor    // 当前扫描线是否处于光标选中行 (用于颜色反转)
);

    // =========================================================================
    // 1. 像素坐标到网格坐标的降维映射 (Pixel to Grid Mapping)
    // =========================================================================
    // UI 区域宽 160 像素，高 480 像素。
    // 除以 8 (右移 3 位) 得到列号 col (0 ~ 19)
    // 除以 16 (右移 4 位) 得到行号 row (0 ~ 29)
    wire [4:0] col = curr_x[7:3]; 
    wire [4:0] row = curr_y[8:4]; 

    // =========================================================================
    // 2. 光标高亮逻辑
    // =========================================================================
    // 规定所有菜单项从第 2 行开始，行间距为 2。物理行号 = 2 + (索引 * 2)
    wire [4:0] active_row = 5'd2 + {1'b0, ui_cursor, 1'b0}; 
    assign is_cursor = (row == active_row) && (col < 5'd12); // 仅高亮前 12 列

    // =========================================================================
    // 3. 动态文本行寄存器 (最大支持 12 个字符 = 96 bits)
    // =========================================================================
    reg [95:0] row_str; 

    // =========================================================================
    // 4. 页面与行内容的硬编码路由矩阵
    // =========================================================================
    always @(*) begin
        // 默认填充空格 (ASCII: 0x20)
        row_str = 96'h2020_2020_2020_2020_2020_2020; 

        // --- A. 常驻底部信息区 (Rows 24-28) ---
        if (row == 5'd24)      row_str = "T_MOD: AUTO ";
        else if (row == 5'd25) row_str = "T_EDG: RISE ";
        else if (row == 5'd26) row_str = "T_LVL: 128  ";
        else if (row == 5'd27) row_str = "T_SRA: 50M  ";
        
        // --- B. 动态菜单区 (Rows 0-20) ---
        else begin
            case (ui_page)
                4'd0: begin // PAGE_MAIN
                    if (row == 5'd0)      row_str = "--- MAIN ---";
                    else if (row == 5'd2) row_str = "1. SRC      ";
                    else if (row == 5'd4) row_str = "2. TRIG     ";
                    else if (row == 5'd6) row_str = "3. DISP     ";
                    else if (row == 5'd8) row_str = "4. STOR     ";
                end
                
                4'd1: begin // PAGE_SRC
                    if (row == 5'd0)       row_str = "--- SRC  ---";
                    else if (row == 5'd2)  row_str = "CH_A        ";
                    else if (row == 5'd4)  row_str = "CH_B        ";
                    else if (row == 5'd6)  row_str = "CH_C        ";
                    else if (row == 5'd8)  row_str = "CH_D        ";
                    else if (row == 5'd10) row_str = "CH_E        ";
                end

                4'd2: begin // PAGE_SRC_CFG
                    if (row == 5'd0)      row_str = "--- CFG  ---";
                    else if (row == 5'd2) row_str = "FREQ: 1KHz  ";
                    else if (row == 5'd4) row_str = "TYPE: SINE  ";
                    else if (row == 5'd6) row_str = "PHAS: 0     ";
                end

                4'd3: begin // PAGE_TRIG
                    if (row == 5'd0)      row_str = "--- TRIG ---";
                    else if (row == 5'd2) row_str = "MODE: AUTO  ";
                    else if (row == 5'd4) row_str = "EDGE: RISE  ";
                    else if (row == 5'd6) row_str = "LEVL: 128   ";
                    else if (row == 5'd8) row_str = "SRAT: 50M   ";
                end

                4'd4: begin // PAGE_DISP
                    if (row == 5'd0)       row_str = "--- DISP ---";
                    else if (row == 5'd2)  row_str = "SRC1: CH_A  ";
                    else if (row == 5'd4)  row_str = "SRC2: CH_B  ";
                    else if (row == 5'd6)  row_str = "SRC3: CH_C  ";
                    else if (row == 5'd8)  row_str = "SRC4: CH_D  ";
                    else if (row == 5'd10) row_str = "T_IN: CH_A  ";
                    else if (row == 5'd12) row_str = "S_IN: CH_1  ";
                    else if (row == 5'd14) row_str = "VIEW: CH_1  "; // 包含 Flash
                end
                
                default: row_str = "            ";
            endcase
        end
    end

    // =========================================================================
    // 5. 字符切片与输出 (String Slicing)
    // =========================================================================
    // Verilog 中的字符串是宽寄存器。最左侧的字符位于最高字节。
    // 当列号 col 为 0 时，我们需要提取 [95:88]。
    // 公式：提取的起始位 = (11 - col) * 8
    always @(*) begin
        if (col < 5'd12) begin
            // 采用移位掩码提取对应的 8-bit ASCII 码
            char_ascii = (row_str >> ((5'd11 - col) * 3'd8)) & 8'hFF;
        end else begin
            char_ascii = 7'h20; // 超出 12 列的部分强制输出空格
        end
    end

endmodule
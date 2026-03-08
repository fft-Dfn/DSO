module hmi_controller (
    input  wire        clk_50m,
    input  wire        rst_n,

    // --- 物理按键输入 (单时钟周期高电平脉冲) ---
    input  wire        key_up_p,
    input  wire        key_down_p,
    input  wire        key_enter_p,
    input  wire        key_back_p,

    // --- 5路独立 DDS 配置输出 ---
    output reg  [31:0] dds_freq_a, dds_freq_b, dds_freq_c, dds_freq_d, dds_freq_e,
    output reg  [1:0]  dds_type_a, dds_type_b, dds_type_c, dds_type_d, dds_type_e,
    output reg  [7:0]  dds_phase_a, dds_phase_b, dds_phase_c, dds_phase_d, dds_phase_e, // 已修正为8位

    // --- 采集模块配置输出 ---
    output reg  [2:0]  sel_trig,    
    output reg  [2:0]  sel_ch1,     
    output reg  [2:0]  sel_ch2,
    output reg  [2:0]  sel_ch3,
    output reg  [2:0]  sel_ch4,
    output reg         trig_mode,   
    output reg         trig_edge,   
    output reg  [7:0]  trig_level,
    output reg  [31:0] sample_div,

    // --- Flash 控制接口 ---
    output reg         flash_write_req,
    output reg  [1:0]  flash_ch_sel, 
    output reg         flash_read_req, 

    // --- VGA 渲染状态输出 ---
    output reg  [3:0]  ui_page,      
    output reg  [3:0]  ui_cursor,    
    output reg  [2:0]  view_ch_sel
);

    // =========================================================================
    // 1. 页面(Page)常量定义
    // =========================================================================
    localparam PAGE_MAIN    = 4'd0;
    localparam PAGE_SRC     = 4'd1;
    localparam PAGE_SRC_CFG = 4'd2;
    localparam PAGE_TRIG    = 4'd3;
    localparam PAGE_DISP    = 4'd4;

    // =========================================================================
    // 2. 内部寄存器定义 (包含5通道的参数数组)
    // =========================================================================
    reg [3:0] curr_page;
    reg [3:0] curr_cursor;
    reg       edit_mode;
    reg [2:0] active_src_ch; // 当前操作的信号源通道 0:A, 1:B, 2:C, 3:D, 4:E

    // 触发与采样离散索引
    reg [2:0] trig_lvl_idx; 
    reg [1:0] samp_div_idx; 

    // 5通道的 DDS 参数离散索引数组
    reg [1:0] freq_idx  [0:4]; 
    reg [1:0] type_idx  [0:4]; 
    reg [1:0] phase_idx [0:4]; 

    integer i;

    // =========================================================================
    // 3. 核心交互状态机
    // =========================================================================
    always @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            curr_page     <= PAGE_MAIN;
            curr_cursor   <= 4'd0;
            edit_mode     <= 1'b0;
            active_src_ch <= 3'd0;
            
            // 全局默认参数
            trig_lvl_idx  <= 3'd2;
            samp_div_idx  <= 2'd0;
            trig_mode     <= 1'b1; // 默认AUTO
            trig_edge     <= 1'b0; // 默认上升沿
            
            // 默认路由配置
            sel_ch1 <= 3'd0; sel_ch2 <= 3'd1; sel_ch3 <= 3'd2; sel_ch4 <= 3'd3;
            sel_trig <= 3'd0;
            view_ch_sel <= 3'd0;
            flash_ch_sel <= 2'd0;

            flash_write_req <= 1'b0;
            flash_read_req  <= 1'b0;

            // 初始化5通道的DDS索引
            for (i = 0; i < 5; i = i + 1) begin
                freq_idx[i]  <= 2'd0;
                type_idx[i]  <= 2'd0;
                phase_idx[i] <= 2'd0;
            end
        end else begin
            flash_write_req <= 1'b0;
            flash_read_req  <= 1'b0;

            // --- 返回键 ---
            if (key_back_p) begin
                if (edit_mode) edit_mode <= 1'b0;
                else begin
                    case (curr_page)
                        PAGE_SRC:     begin curr_page <= PAGE_MAIN; curr_cursor <= 4'd0; end
                        PAGE_SRC_CFG: begin curr_page <= PAGE_SRC;  curr_cursor <= active_src_ch; end
                        PAGE_TRIG:    begin curr_page <= PAGE_MAIN; curr_cursor <= 4'd1; end
                        PAGE_DISP:    begin curr_page <= PAGE_MAIN; curr_cursor <= 4'd2; end
                        default:      curr_page <= PAGE_MAIN;
                    endcase
                end
            end

            // --- 导航模式 ---
            else if (!edit_mode) begin
                if (key_up_p) begin
                    if (curr_cursor > 0) curr_cursor <= curr_cursor - 1'b1;
                end
                else if (key_down_p) begin
                    case (curr_page)
                        PAGE_MAIN:    if (curr_cursor < 3) curr_cursor <= curr_cursor + 1'b1;
                        PAGE_SRC:     if (curr_cursor < 4) curr_cursor <= curr_cursor + 1'b1; 
                        PAGE_SRC_CFG: if (curr_cursor < 2) curr_cursor <= curr_cursor + 1'b1; 
                        PAGE_TRIG:    if (curr_cursor < 3) curr_cursor <= curr_cursor + 1'b1; 
                        PAGE_DISP:    if (curr_cursor < 6) curr_cursor <= curr_cursor + 1'b1; 
                    endcase
                end
                else if (key_enter_p) begin
                    case (curr_page)
                        PAGE_MAIN: begin
                            if (curr_cursor == 4'd0)      begin curr_page <= PAGE_SRC;  curr_cursor <= 4'd0; end
                            else if (curr_cursor == 4'd1) begin curr_page <= PAGE_TRIG; curr_cursor <= 4'd0; end
                            else if (curr_cursor == 4'd2) begin curr_page <= PAGE_DISP; curr_cursor <= 4'd0; end
                            else if (curr_cursor == 4'd3) flash_write_req <= 1'b1; 
                        end
                        PAGE_SRC: begin
                            active_src_ch <= curr_cursor[2:0]; 
                            curr_page <= PAGE_SRC_CFG;
                            curr_cursor <= 4'd0;
                        end
                        PAGE_SRC_CFG, PAGE_TRIG, PAGE_DISP: edit_mode <= 1'b1;
                    endcase
                end
            end

            // --- 编辑模式 ---
            else if (edit_mode) begin
                if (key_enter_p) begin
                    edit_mode <= 1'b0; 
                    if (curr_page == PAGE_DISP && curr_cursor == 4'd6 && view_ch_sel == 3'd4) 
                        flash_read_req <= 1'b1;
                end
                else if (key_up_p) begin
                    case (curr_page)
                        PAGE_SRC_CFG: begin
                            if (curr_cursor == 4'd0 && freq_idx[active_src_ch] < 3)  freq_idx[active_src_ch]  <= freq_idx[active_src_ch] + 1'b1;
                            if (curr_cursor == 4'd1 && type_idx[active_src_ch] < 2)  type_idx[active_src_ch]  <= type_idx[active_src_ch] + 1'b1;
                            if (curr_cursor == 4'd2 && phase_idx[active_src_ch] < 3) phase_idx[active_src_ch] <= phase_idx[active_src_ch] + 1'b1;
                        end
                        PAGE_TRIG: begin
                            if (curr_cursor == 4'd0) trig_mode <= 1'b1;
                            if (curr_cursor == 4'd1) trig_edge <= 1'b1;
                            if (curr_cursor == 4'd2 && trig_lvl_idx < 4) trig_lvl_idx <= trig_lvl_idx + 1'b1;
                            if (curr_cursor == 4'd3 && samp_div_idx < 3) samp_div_idx <= samp_div_idx + 1'b1;
                        end
                        PAGE_DISP: begin
                            if (curr_cursor == 4'd0 && sel_ch1 < 4) sel_ch1 <= sel_ch1 + 1'b1;
                            if (curr_cursor == 4'd1 && sel_ch2 < 4) sel_ch2 <= sel_ch2 + 1'b1;
                            if (curr_cursor == 4'd2 && sel_ch3 < 4) sel_ch3 <= sel_ch3 + 1'b1;
                            if (curr_cursor == 4'd3 && sel_ch4 < 4) sel_ch4 <= sel_ch4 + 1'b1;
                            if (curr_cursor == 4'd4 && sel_trig < 4) sel_trig <= sel_trig + 1'b1;
                            if (curr_cursor == 4'd5 && flash_ch_sel < 3) flash_ch_sel <= flash_ch_sel + 1'b1;
                            if (curr_cursor == 4'd6 && view_ch_sel < 4) view_ch_sel <= view_ch_sel + 1'b1;
                        end
                    endcase
                end
                else if (key_down_p) begin
                    case (curr_page)
                        PAGE_SRC_CFG: begin
                            if (curr_cursor == 4'd0 && freq_idx[active_src_ch] > 0)  freq_idx[active_src_ch]  <= freq_idx[active_src_ch] - 1'b1;
                            if (curr_cursor == 4'd1 && type_idx[active_src_ch] > 0)  type_idx[active_src_ch]  <= type_idx[active_src_ch] - 1'b1;
                            if (curr_cursor == 4'd2 && phase_idx[active_src_ch] > 0) phase_idx[active_src_ch] <= phase_idx[active_src_ch] - 1'b1;
                        end
                        PAGE_TRIG: begin
                            if (curr_cursor == 4'd0) trig_mode <= 1'b0;
                            if (curr_cursor == 4'd1) trig_edge <= 1'b0;
                            if (curr_cursor == 4'd2 && trig_lvl_idx > 0) trig_lvl_idx <= trig_lvl_idx - 1'b1;
                            if (curr_cursor == 4'd3 && samp_div_idx > 0) samp_div_idx <= samp_div_idx - 1'b1;
                        end
                        PAGE_DISP: begin
                            if (curr_cursor == 4'd0 && sel_ch1 > 0) sel_ch1 <= sel_ch1 - 1'b1;
                            if (curr_cursor == 4'd1 && sel_ch2 > 0) sel_ch2 <= sel_ch2 - 1'b1;
                            if (curr_cursor == 4'd2 && sel_ch3 > 0) sel_ch3 <= sel_ch3 - 1'b1;
                            if (curr_cursor == 4'd3 && sel_ch4 > 0) sel_ch4 <= sel_ch4 - 1'b1;
                            if (curr_cursor == 4'd4 && sel_trig > 0) sel_trig <= sel_trig - 1'b1;
                            if (curr_cursor == 4'd5 && flash_ch_sel > 0) flash_ch_sel <= flash_ch_sel - 1'b1;
                            if (curr_cursor == 4'd6 && view_ch_sel > 0) view_ch_sel <= view_ch_sel - 1'b1;
                        end
                    endcase
                end
            end
        end
    end

    always @(posedge clk_50m) begin
        ui_page   <= curr_page;
        ui_cursor <= curr_cursor;
    end

    // =========================================================================
    // 4. LUT 映射逻辑：将离散索引转化为物理输出
    // =========================================================================

    // 触发参数
    always @(*) begin
        case (trig_lvl_idx)
            3'd0: trig_level = 8'd25;
            3'd1: trig_level = 8'd75;
            3'd2: trig_level = 8'd128;
            3'd3: trig_level = 8'd180;
            3'd4: trig_level = 8'd230;
            default: trig_level = 8'd128;
        endcase

        case (samp_div_idx)
            2'd0: sample_div = 32'd1;   
            2'd1: sample_div = 32'd5;   
            2'd2: sample_div = 32'd50;  
            2'd3: sample_div = 32'd500; 
            default: sample_div = 32'd1;
        endcase
    end

    // 离散参数到 DDS 频率控制字的映射函数
    function [31:0] get_freq_word(input [1:0] idx);
        case (idx)
            2'd0: get_freq_word = 32'd85899;   // 1kHz
            2'd1: get_freq_word = 32'd858993;  // 10kHz
            2'd2: get_freq_word = 32'd8589934; // 100kHz
            2'd3: get_freq_word = 32'd85899345;// 1MHz
        endcase
    endfunction

    // 离散参数到 DDS 相位偏移(8位)的映射函数
    function [7:0] get_phase_word(input [1:0] idx);
        case (idx)
            2'd0: get_phase_word = 8'd0;   // 0度
            2'd1: get_phase_word = 8'd64;  // 90度
            2'd2: get_phase_word = 8'd128; // 180度
            2'd3: get_phase_word = 8'd192; // 270度
        endcase
    endfunction

    // 将数组索引解析为各通道输出
    always @(*) begin
        dds_freq_a = get_freq_word(freq_idx[0]);
        dds_type_a = type_idx[0];
        dds_phase_a = get_phase_word(phase_idx[0]);

        dds_freq_b = get_freq_word(freq_idx[1]);
        dds_type_b = type_idx[1];
        dds_phase_b = get_phase_word(phase_idx[1]);

        dds_freq_c = get_freq_word(freq_idx[2]);
        dds_type_c = type_idx[2];
        dds_phase_c = get_phase_word(phase_idx[2]);

        dds_freq_d = get_freq_word(freq_idx[3]);
        dds_type_d = type_idx[3];
        dds_phase_d = get_phase_word(phase_idx[3]);

        dds_freq_e = get_freq_word(freq_idx[4]);
        dds_type_e = type_idx[4];
        dds_phase_e = get_phase_word(phase_idx[4]);
    end

endmodule
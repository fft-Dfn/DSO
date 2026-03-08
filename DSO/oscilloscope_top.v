module oscilloscope_top (
    // --- 硬件系统时钟与复位 ---
    input  wire        sys_clk_50m, 
    
    input  wire        sys_rst_n,   
    input  wire        key_up_n,
    input  wire        key_down_n,
    input  wire        key_enter_n,
    input  wire        key_back_n,

    // --- VGA 物理 DAC 接口 ---
    output wire        vga_hs,
    output wire        vga_vs,
    output wire        vga_blank,
    output wire [7:0]  vga_r,
    output wire [7:0]  vga_g,
    output wire [7:0]  vga_b,

    // --- SPI Flash 硬件接口  ---
    output wire        flash_cs_n,
    output wire        flash_sck,
    output wire        flash_mosi,
    input  wire        flash_miso
);

// =========================================================================
    // 0. 时钟与全局网络管理 
    // =========================================================================
    wire clk_50m; 
    wire clk_25m; 
    wire pll_locked;

    // (时钟分频逻辑保留，供仿真使用)PLL
    assign clk_50m = sys_clk_50m;
    reg clk_25m_reg;
    always @(posedge clk_50m or posedge sys_rst_n) begin
        if (!sys_rst_n) clk_25m_reg <= 1'b0;
        else clk_25m_reg <= ~clk_25m_reg;
    end
    assign clk_25m = clk_25m_reg;
    assign pll_locked = 1'b1;

    // =========================================================================
    // 1. 全局硬件消抖矩阵
    // =========================================================================
    wire [4:0] raw_keys = {sys_rst_n, key_up_n, key_down_n, key_enter_n, key_back_n};
    wire [4:0] clean_keys;

    key_debouncer #(
        .KEY_WIDTH (5),
        .WAIT_TIME (20'd1_000_000)
    ) u_key_debouncer ( 
        .clk_50m   (clk_50m),
        .key_raw   (raw_keys),
        .key_clean (clean_keys)
    );

    // =========================================================================
    // 2. 干净的复位树与按键脉冲提取
    // =========================================================================
    // 提取消抖后的系统复位按键
    wire clean_rst_n = clean_keys[4];
    
    // 全局复位 = 消抖后的复位按键 &PLL 锁定状态
    wire global_rst_n = clean_rst_n & pll_locked;
    wire clean_key_up_n    = clean_keys[3];
    wire clean_key_down_n  = clean_keys[2];
    wire clean_key_enter_n = clean_keys[1];
    wire clean_key_back_n  = clean_keys[0];

    reg [3:0] key_d0, key_d1;
    always @(posedge clk_50m or negedge global_rst_n) begin
        if (!global_rst_n) begin
            key_d0 <= 4'b1111;
            key_d1 <= 4'b1111;
        end else begin
            // 此时送入边缘检测(交换按钮的下降沿)
            key_d0 <= {clean_key_up_n, clean_key_down_n, clean_key_enter_n, clean_key_back_n};
            key_d1 <= key_d0;
        end
    end
    
    wire key_up_p    = ~key_d0[3] & key_d1[3];
    wire key_down_p  = ~key_d0[2] & key_d1[2];
    wire key_enter_p = ~key_d0[1] & key_d1[1];
    wire key_back_p  = ~key_d0[0] & key_d1[0];

    // =========================================================================
    // 3. 主控状态机 (HMI Controller)
    // =========================================================================
    wire [31:0] dds_freq_a;
    wire [1:0]  dds_type_a;
    wire [7:0]  dds_phase_a;
    wire [31:0] dds_freq_b;
    wire [1:0]  dds_type_b;
    wire [7:0]  dds_phase_b;
    wire [31:0] dds_freq_c;
    wire [1:0]  dds_type_c;
    wire [7:0]  dds_phase_c;
    wire [31:0] dds_freq_d;
    wire [1:0]  dds_type_d;
    wire [7:0]  dds_phase_d;
    wire [31:0] dds_freq_e;
    wire [1:0]  dds_type_e;
    wire [7:0]  dds_phase_e;
    
    wire [2:0]  sel_trig, sel_ch1, sel_ch2, sel_ch3, sel_ch4;
    
    wire        trig_mode, trig_edge;
    wire [7:0]  trig_level;
    wire [31:0] sample_div;

    wire        flash_write_req, flash_read_req;
    wire [1:0]  flash_ch_sel;

    wire [3:0]  ui_page;
    wire [3:0]  ui_cursor;
    wire [2:0]  view_ch_sel;

    hmi_controller u_hmi_controller (
        .clk_50m         (clk_50m),
        .rst_n           (global_rst_n),
        .key_up_p        (key_up_p),
        .key_down_p      (key_down_p),
        .key_enter_p     (key_enter_p),
        .key_back_p      (key_back_p),
        
        .dds_freq_a      (dds_freq_a),
        .dds_type_a      (dds_type_a),
        .dds_phase_a     (dds_phase_a),
        .dds_freq_b      (dds_freq_b),
        .dds_type_b      (dds_type_b),
        .dds_phase_b     (dds_phase_b),
        .dds_freq_c      (dds_freq_c),
        .dds_type_c      (dds_type_c),
        .dds_phase_c     (dds_phase_c),
        .dds_freq_d     (dds_freq_d),
        .dds_type_d      (dds_type_d),
        .dds_phase_d     (dds_phase_d),
        .dds_freq_e      (dds_freq_e),
        .dds_type_e      (dds_type_e),
        .dds_phase_e     (dds_phase_e),
        
        .sel_trig        (sel_trig),
        .sel_ch1         (sel_ch1),
        .sel_ch2         (sel_ch2),
        .sel_ch3         (sel_ch3),
        .sel_ch4         (sel_ch4),
        
        .trig_mode       (trig_mode),
        .trig_edge       (trig_edge),
        .trig_level      (trig_level),
        .sample_div      (sample_div),
        
        .flash_write_req (flash_write_req),
        .flash_ch_sel    (flash_ch_sel),
        .flash_read_req  (flash_read_req),
        
        .ui_page         (ui_page),
        .ui_cursor       (ui_cursor),
        .view_ch_sel     (view_ch_sel)
    );

// =========================================================================
    // 4. 内部信号源矩阵 (Internal Signal Matrix)
    // =========================================================================
    wire [7:0] sig_a, sig_b, sig_c, sig_d, sig_e;
    
    dds_generator a_dds_generator(
        .clk(clk_50m),
        .rst_n(global_rst_n),
        .freq_word(dds_freq_a),   
        .phase_offset(dds_phase_a), 
        .wave_type(dds_type_a),
        .wave_data(sig_a)
    );
    dds_generator b_dds_generator(
        .clk(clk_50m),
        .rst_n(global_rst_n),
        .freq_word(dds_freq_b),   
        .phase_offset(dds_phase_b), 
        .wave_type(dds_type_b),
        .wave_data(sig_b)
    );
    dds_generator c_dds_generator(
        .clk(clk_50m),
        .rst_n(global_rst_n),
        .freq_word(dds_freq_c),   
        .phase_offset(dds_phase_c), 
        .wave_type(dds_type_c),
        .wave_data(sig_c)
    );
    dds_generator d_dds_generator(
        .clk(clk_50m),
        .rst_n(global_rst_n),
        .freq_word(dds_freq_d),   
        .phase_offset(dds_phase_d), 
        .wave_type(dds_type_d),
        .wave_data(sig_d)
    );
    dds_generator e_dds_generator(
        .clk(clk_50m),
        .rst_n(global_rst_n),
        .freq_word(dds_freq_e),   
        .phase_offset(dds_phase_e), 
        .wave_type(dds_type_e),
        .wave_data(sig_e)
    );
    
    // =========================================================================
    // 5. 采集触发引擎
    // =========================================================================
    wire        ram_we;
    wire [9:0]  ram_waddr;
    wire [7:0]  ram_wdata_ch1, ram_wdata_ch2, ram_wdata_ch3, ram_wdata_ch4;
    wire        capture_done;

    sample_controller u_sample_controller (
        .clk           (clk_50m),
        .rst_n         (global_rst_n),
        .in_a          (sig_a),
        .in_b          (sig_b),
        .in_c          (sig_c),
        .in_d          (sig_d),
        .in_e          (sig_e),
        .sel_trig      (sel_trig),
        .sel_ch1       (sel_ch1),
        .sel_ch2       (sel_ch2),
        .sel_ch3       (sel_ch3),
        .sel_ch4       (sel_ch4),
        .trig_mode     (trig_mode),
        .trig_edge     (trig_edge),
        .trig_level    (trig_level),
        .sample_div    (sample_div),
        
        .rearm         (1'b1), 
        .capture_done  (capture_done),
        
        .ram_we        (ram_we),
        .ram_waddr     (ram_waddr),
        .ram_wdata_ch1 (ram_wdata_ch1),
        .ram_wdata_ch2 (ram_wdata_ch2),
        .ram_wdata_ch3 (ram_wdata_ch3),
        .ram_wdata_ch4 (ram_wdata_ch4)
    );

    // =========================================================================
    // 6. 双缓存BRAM
    // =========================================================================
    wire [9:0] vga_wave_raddr;
    wire [7:0] rdata_ch1, rdata_ch2, rdata_ch3, rdata_ch4;

    pingpong_bram_buffer u_pingpong_bram_buffer (
        .rst_n         (global_rst_n),
        .clk_write     (clk_50m),
        .we            (ram_we),
        .waddr         (ram_waddr),
        .wdata_ch1     (ram_wdata_ch1),
        .wdata_ch2     (ram_wdata_ch2),
        .wdata_ch3     (ram_wdata_ch3),
        .wdata_ch4     (ram_wdata_ch4),
        .capture_done  (capture_done),
        
        .clk_read      (clk_25m),
        .raddr         (vga_wave_raddr),
        .rdata_ch1     (rdata_ch1),
        .rdata_ch2     (rdata_ch2),
        .rdata_ch3     (rdata_ch3),
        .rdata_ch4     (rdata_ch4)
    );

    // =========================================================================
    // 7. 显示通道读取路由
    // =========================================================================
    wire [7:0] rdata_flash = 8'd128; 
    
    
    
    wire [7:0] vga_wave_rdata;

    assign vga_wave_rdata = (view_ch_sel == 3'd0) ? rdata_ch1 :
                            (view_ch_sel == 3'd1) ? rdata_ch2 :
                            (view_ch_sel == 3'd2) ? rdata_ch3 :
                            (view_ch_sel == 3'd3) ? rdata_ch4 :
                            (view_ch_sel == 3'd4) ? rdata_flash : 8'd0;

    // =========================================================================
    // 8. VGA 显示子系统
    // =========================================================================
    vga_subsystem_top u_vga_subsystem_top (
        .clk_25m       (clk_25m),
        .rst_n         (global_rst_n),
        .ui_page       (ui_page),
        .ui_cursor     (ui_cursor),
        .view_ch_sel   (view_ch_sel),
        
        .wave_raddr    (vga_wave_raddr),
        .wave_rdata    (vga_wave_rdata),
        .vga_hs        (vga_hs),
        .vga_vs        (vga_vs),
        .vga_blank     (vga_blank),
        .vga_r         (vga_r),
        .vga_g         (vga_g),
        .vga_b         (vga_b)
    );

endmodule
module DSO_project (
    input  wire        clk_50m,
    input  wire        clk_25m,
    input  wire        pll_locked,

    input  wire        sys_rst_n,

    input  wire        key_up_n,
    input  wire        key_down_n,
    input  wire        key_enter_n,
    input  wire        key_back_n,

    output wire        vga_hs,
    output wire        vga_vs,
    output wire [4:0]  vga_r,
    output wire [5:0]  vga_g,
    output wire [4:0]  vga_b,
    
    output wire        led_0
 
   // output wire        flash_cs_n,
    //output wire        flash_sck,
    //output wire        flash_mosi,
    //input  wire        flash_miso
);
//物理消抖
    wire [4:0] raw_keys = {sys_rst_n, key_up_n, key_down_n, key_enter_n, key_back_n};
    wire [4:0] clean_keys;
    key_debouncer #(
        .KEY_WIDTH(5),
        .WAIT_TIME(20'd1_000_000)
    ) u_key_debouncer (
        .clk_50m  (clk_50m),
        .key_raw  (raw_keys),
        .key_clean(clean_keys)
    );

    
 
    wire clean_rst_n       = clean_keys[4];
    wire global_rst_n      = clean_rst_n & pll_locked;
    wire clean_key_up_n    = clean_keys[3];
    wire clean_key_down_n  = clean_keys[2];
    wire clean_key_enter_n = clean_keys[1];
    wire clean_key_back_n  = clean_keys[0];
    
//边沿检测
    reg [3:0] key_d0, key_d1;
    always @(posedge clk_50m or negedge global_rst_n) begin
        if (!global_rst_n) begin
            key_d0 <= 4'b1111;
            key_d1 <= 4'b1111;
        end else begin
            key_d0 <= {clean_key_up_n, clean_key_down_n, clean_key_enter_n, clean_key_back_n};
            key_d1 <= key_d0;
        end
    end

    wire key_up_p    = ~key_d0[3] & key_d1[3];
    wire key_down_p  = ~key_d0[2] & key_d1[2];
    wire key_enter_p = ~key_d0[1] & key_d1[1];
    wire key_back_p  = ~key_d0[0] & key_d1[0];

    
//交互控制
    wire [31:0] dds_freq_a, dds_freq_b, dds_freq_c, dds_freq_d, dds_freq_e;
    wire [1:0]  dds_type_a, dds_type_b, dds_type_c, dds_type_d, dds_type_e;
    wire [7:0]  dds_phase_a, dds_phase_b, dds_phase_c, dds_phase_d, dds_phase_e;
    
    wire [2:0]  sel_trig, sel_ch1, sel_ch2, sel_ch3, sel_ch4;
    wire        trig_mode, trig_edge;
    wire [7:0]  trig_level;
    wire [31:0] sample_div;
    
    wire        flash_write_req, flash_read_req;
    wire [1:0]  flash_ch_sel;

    wire [3:0]  ui_page, ui_cursor;
    wire [2:0]  view_ch_sel;
    wire        ui_curr_edit_mode;
    wire [3:0]  ui_curr_edit_value;
    wire [2:0]  ui_active_src_sel;



    hmi_controller u_hmi_controller (
        .clk_50m        (clk_50m),
        .rst_n          (global_rst_n),

        .key_up_p       (key_up_p),
        .key_down_p     (key_down_p),
        .key_enter_p    (key_enter_p),
        .key_back_p     (key_back_p),

        .dds_freq_a     (dds_freq_a),
        .dds_freq_b     (dds_freq_b),
        .dds_freq_c     (dds_freq_c),
        .dds_freq_d     (dds_freq_d),
        .dds_freq_e     (dds_freq_e),
        .dds_type_a     (dds_type_a),
        .dds_type_b     (dds_type_b),
        .dds_type_c     (dds_type_c),
        .dds_type_d     (dds_type_d),
        .dds_type_e     (dds_type_e),
        .dds_phase_a    (dds_phase_a),
        .dds_phase_b    (dds_phase_b),
        .dds_phase_c    (dds_phase_c),
        .dds_phase_d    (dds_phase_d),
        .dds_phase_e    (dds_phase_e),

        .sel_trig       (sel_trig),
        .sel_ch1        (sel_ch1),
        .sel_ch2        (sel_ch2),
        .sel_ch3        (sel_ch3),
        .sel_ch4        (sel_ch4),
        .trig_mode      (trig_mode),
        .trig_edge      (trig_edge),
        .trig_level     (trig_level),
        .sample_div     (sample_div),
       
        
        .flash_write_req(flash_write_req),
        .flash_ch_sel   (flash_ch_sel),
        .flash_read_req (flash_read_req),

        .ui_page        (ui_page),
        .ui_cursor      (ui_cursor),
        .ui_curr_edit_mode  (ui_curr_edit_mode),
        .ui_curr_edit_value  (ui_curr_edit_value),
        .ui_active_src_sel   (ui_active_src_sel),
        .view_ch_sel    (view_ch_sel)
    );
 



//信号发生器
    wire [7:0] sig_a, sig_b, sig_c, sig_d, sig_e;
    dds_generator u_dds_a (.clk(clk_50m), .rst_n(global_rst_n), .freq_word(dds_freq_a), .phase_offset(dds_phase_a), .wave_type(dds_type_a), .wave_data(sig_a));
    dds_generator u_dds_b (.clk(clk_50m), .rst_n(global_rst_n), .freq_word(dds_freq_b), .phase_offset(dds_phase_b), .wave_type(dds_type_b), .wave_data(sig_b));
    dds_generator u_dds_c (.clk(clk_50m), .rst_n(global_rst_n), .freq_word(dds_freq_c), .phase_offset(dds_phase_c), .wave_type(dds_type_c), .wave_data(sig_c));
    dds_generator u_dds_d (.clk(clk_50m), .rst_n(global_rst_n), .freq_word(dds_freq_d), .phase_offset(dds_phase_d), .wave_type(dds_type_d), .wave_data(sig_d));
    dds_generator u_dds_e (.clk(clk_50m), .rst_n(global_rst_n), .freq_word(dds_freq_e), .phase_offset(dds_phase_e), .wave_type(dds_type_e), .wave_data(sig_e));
//采样控制器
    wire              ram_we;
    wire [9:0]        ram_waddr;
    wire [7:0]        ram_wdata_ch1, ram_wdata_ch2, ram_wdata_ch3, ram_wdata_ch4;
    wire              capture_done;
    wire [9:0]        frame_start_addr;

    sample_controller u_sample_controller (
        .clk             (clk_50m),
        .rst_n           (global_rst_n),

        .in_a            (sig_a),
        .in_b            (sig_b),
        .in_c            (sig_c),
        .in_d            (sig_d),
        .in_e            (sig_e),

        .sel_trig        (sel_trig),
        .sel_ch1         (sel_ch1),
        .sel_ch2         (sel_ch2),
        .sel_ch3         (sel_ch3),
        .sel_ch4         (sel_ch4),
        .trig_mode       (trig_mode),
        .trig_edge       (trig_edge),
        .trig_level      (trig_level),
        .sample_div      (sample_div),

        .rearm           (1'b1),
        .capture_done    (capture_done),
        .frame_start_addr(frame_start_addr),
        .ram_we          (ram_we),
        
        .ram_waddr       (ram_waddr),
        .ram_wdata_ch1   (ram_wdata_ch1),
        .ram_wdata_ch2   (ram_wdata_ch2),
        .ram_wdata_ch3   (ram_wdata_ch3),
        .ram_wdata_ch4   (ram_wdata_ch4)
    );
   
    // 双缓存
    //wire [9:0] vga_wave_phys_raddr = active_frame_start_addr + vga_wave_logical_raddr;
    wire [9:0] active_frame_start_addr;
    wire       frame_valid;
    wire [7:0] vga_rdata_ch1, vga_rdata_ch2, vga_rdata_ch3, vga_rdata_ch4;
    wire       rd_frame_done;
    wire       [9:0] vga_raddr;
    wire       overflow;
    


    pingpong_buffer u_pingpong_buffer (
        .rst_n                   (global_rst_n),

        .clk_write               (clk_50m),
        .waddr                   (ram_waddr),
        .wdata_ch1               (ram_wdata_ch1),
        .wdata_ch2               (ram_wdata_ch2),
        .wdata_ch3               (ram_wdata_ch3),
        .wdata_ch4               (ram_wdata_ch4),

        .clk_read                (clk_25m),//不能随便换时钟域
        .raddr                   (vga_raddr),
        .rdata_ch1               (vga_rdata_ch1),
        .rdata_ch2               (vga_rdata_ch2),
        .rdata_ch3               (vga_rdata_ch3),
        .rdata_ch4               (vga_rdata_ch4),

        .capture_done            (capture_done),
        .we                      (ram_we),
        .rd_frame_done    (rd_frame_done),    // 读侧声明：当前帧已经读完（读域脉冲
        .overflow          (overflow),
        .frame_start_addr     (frame_start_addr),
        .active_frame_start_addr     (active_frame_start_addr),
        .frame_valid      (frame_valid)
        

    );
    
    
    
   assign  led_0 = ~overflow;
   wire [15:0] rgb_565;
   assign vga_r     = rgb_565[15:11];
   assign vga_g     = rgb_565[10:5];
   assign vga_b     = rgb_565[4:0];
   
    VGA_top u_VGA_top(/*AUTOINST*/
		      // Outputs
		      .raddr		(vga_raddr),
		      .rd_frame_done	(rd_frame_done),
		      .hsync		(vga_hs),
		      .vsync		(vga_vs),
		      .rgb565		(rgb_565),
		      // Inputs
		      .clk_25m		(clk_25m),
		      .rst_n		(global_rst_n),
		      .frame_valid	(frame_valid),
		      .active_frame_start_addr(active_frame_start_addr),
		      .rdata_ch1	(vga_rdata_ch1),
		      .rdata_ch2	(vga_rdata_ch2),
		      .rdata_ch3	(vga_rdata_ch3),
		      .rdata_ch4	(vga_rdata_ch4)

		      //.ui_page		(ui_page),
		      //.ui_cursor	(ui_cursor),
		      //.ui_curr_edit_mode(ui_curr_edit_mode),
		      //.ui_curr_edit_valu(ui_curr_edit_valu),
		      //.ui_active_src_sel(ui_active_src_sel),
		      //.view_ch_sel	(view_ch_sel)
          );
   
endmodule

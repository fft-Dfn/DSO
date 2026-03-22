module pingpong_buffer #(
    parameter DATA_W = 8,
    parameter ADDR_W = 10
)(
    input  wire                  rst_n,

    // 写侧
    input  wire                  clk_write,
    input  wire [ADDR_W-1:0]     waddr,
    input  wire [DATA_W-1:0]     wdata_ch1,
    input  wire [DATA_W-1:0]     wdata_ch2,
    input  wire [DATA_W-1:0]     wdata_ch3,
    input  wire [DATA_W-1:0]     wdata_ch4,

    // 读侧
    input  wire                  clk_read,
    input  wire [ADDR_W-1:0]     raddr,
    output reg  [DATA_W-1:0]     rdata_ch1,
    output reg  [DATA_W-1:0]     rdata_ch2,
    output reg  [DATA_W-1:0]     rdata_ch3,
    output reg  [DATA_W-1:0]     rdata_ch4,

    // 状态
    input  wire                  capture_done,         // 写域脉冲：当前拍是本帧最后一个点
    input  wire                  we,                   // 写域写使能
    output reg                   frame_valid,          // 读域：当前有完整帧可读
    input  wire                  rd_frame_done,        // 读域脉冲：当前帧读完
    output reg                   overflow,             // 写域：提交时没有空闲bank可切换
    input  wire [ADDR_W-1:0]     frame_start_addr,     // 写域：capture_done当拍对应帧的起始地址
    output reg  [ADDR_W-1:0]     active_frame_start_addr
    
);

   
    // bank状态（写域）
    localparam [1:0] BANK_FREE    = 2'd0;
    localparam [1:0] BANK_WRITING = 2'd1;
    localparam [1:0] BANK_READY   = 2'd2;

    reg [1:0] bank0_state_wr;
    reg [1:0] bank1_state_wr;

    // 当前写bank
    reg wr_bank;

    // 每个bank对应的帧起始地址（写域锁存，直到该bank被release）
    reg [ADDR_W-1:0] frame_start_addr_bank0_wr;
    reg [ADDR_W-1:0] frame_start_addr_bank1_wr;

    // 写域 -> 读域：commit toggle（每个bank一个）
    reg commit_tog_bank0_wr;
    reg commit_tog_bank1_wr;

    reg commit0_rd_sync1, commit0_rd_sync2, commit0_rd_sync2_d;
    reg commit1_rd_sync1, commit1_rd_sync2, commit1_rd_sync2_d;

    wire commit_bank0_pulse_rd;
    wire commit_bank1_pulse_rd;

    assign commit_bank0_pulse_rd = commit0_rd_sync2 ^ commit0_rd_sync2_d;
    assign commit_bank1_pulse_rd = commit1_rd_sync2 ^ commit1_rd_sync2_d;


    //  读域 -> 写域：release toggle（每个bank一个）
    reg release_tog_bank0_rd;
    reg release_tog_bank1_rd;

    reg release0_wr_sync1, release0_wr_sync2, release0_wr_sync2_d;
    reg release1_wr_sync1, release1_wr_sync2, release1_wr_sync2_d;

    wire release_bank0_pulse_wr;
    wire release_bank1_pulse_wr;

    assign release_bank0_pulse_wr = release0_wr_sync2 ^ release0_wr_sync2_d;
    assign release_bank1_pulse_wr = release1_wr_sync2 ^ release1_wr_sync2_d;

    // frame_start_addr 跨域同步
    reg [ADDR_W-1:0] frame_start_addr_bank0_rd_sync1, frame_start_addr_bank0_rd_sync2;
    reg [ADDR_W-1:0] frame_start_addr_bank1_rd_sync1, frame_start_addr_bank1_rd_sync2;

    // 读域内部：active / pending
    reg              active_bank_rd;
    reg              pending_valid;
    reg              pending_bank_rd;
    reg [ADDR_W-1:0] pending_frame_start_addr;

    // 写域辅助
    wire bank0_free_now_wr;
    wire bank1_free_now_wr;
    wire curr_bank_is_writing;
    wire other_bank_free_now;

    assign bank0_free_now_wr =
        (bank0_state_wr == BANK_FREE) || release_bank0_pulse_wr;

    assign bank1_free_now_wr =
        (bank1_state_wr == BANK_FREE) || release_bank1_pulse_wr;

    assign curr_bank_is_writing =
        (wr_bank == 1'b0) ? (bank0_state_wr == BANK_WRITING)
                          : (bank1_state_wr == BANK_WRITING);

    assign other_bank_free_now =
        (wr_bank == 1'b0) ? bank1_free_now_wr
                          : bank0_free_now_wr;

    //  BRAM IP 打包写入 / 读出
    wire [31:0] wdata_packed;
    assign wdata_packed = {wdata_ch4, wdata_ch3, wdata_ch2, wdata_ch1};

    wire        bank0_we_a;
    wire        bank1_we_a;
    
  //  assign bank0_we_a = we;
  //  assign bank1_we_a = 1'b0;
    assign bank0_we_a = we && curr_bank_is_writing && (wr_bank == 1'b0);
    assign bank1_we_a = we && curr_bank_is_writing && (wr_bank == 1'b1);

    wire [31:0] bank0_rdata_b;
    wire [31:0] bank1_rdata_b;
    wire [31:0] bank0_rdata_a_unused;
    wire [31:0] bank1_rdata_a_unused;


    // bank0
    pingpong_bram_refact u_pingpong_bram_bank0 (
        .we_a    (bank0_we_a),
        .addr_a  (waddr),
        .wdata_a (wdata_packed),
        .rdata_a (bank0_rdata_a_unused),
        
        .rdata_b (bank0_rdata_b),
        .addr_b  (raddr),
        .wdata_b (32'd0),
        .clk_a   (clk_write),
        .clk_b   (clk_read)


    );

    // bank1
    pingpong_bram_refact u_pingpong_bram_bank1 (
        .we_a    (bank1_we_a),
        .addr_a  (waddr),
        .wdata_a (wdata_packed),
        .rdata_a (bank1_rdata_a_unused),

        .rdata_b (bank1_rdata_b),
        .addr_b  (raddr),
        .wdata_b (32'd0),
        .clk_a   (clk_write),
        .clk_b   (clk_read)

    );

    // ============================================================
    //  写域主逻辑
    //
    // capture_done 与最后一个 we 同拍：
    // 1. 当前拍写入最后一个样本
    // 2. 同拍提交当前bank为READY
    // ============================================================
    always @(posedge clk_write or negedge rst_n) begin
        if (!rst_n) begin
            wr_bank                   <= 1'b0;

            bank0_state_wr            <= BANK_WRITING; // 上电先写bank0
            bank1_state_wr            <= BANK_FREE;

            frame_start_addr_bank0_wr <= {ADDR_W{1'b0}};
            frame_start_addr_bank1_wr <= {ADDR_W{1'b0}};

            commit_tog_bank0_wr       <= 1'b0;
            commit_tog_bank1_wr       <= 1'b0;

            release0_wr_sync1         <= 1'b0;
            release0_wr_sync2         <= 1'b0;
            release0_wr_sync2_d       <= 1'b0;
            release1_wr_sync1         <= 1'b0;
            release1_wr_sync2         <= 1'b0;
            release1_wr_sync2_d       <= 1'b0;

            overflow                  <= 1'b0;
        end else begin
            // 同步release toggle到写域
            release0_wr_sync1   <= release_tog_bank0_rd;
            release0_wr_sync2   <= release0_wr_sync1;
            release0_wr_sync2_d <= release0_wr_sync2;

            release1_wr_sync1   <= release_tog_bank1_rd;
            release1_wr_sync2   <= release1_wr_sync1;
            release1_wr_sync2_d <= release1_wr_sync2;

            // READY -> FREE
            if (release_bank0_pulse_wr) begin
                if (bank0_state_wr == BANK_READY)
                    bank0_state_wr <= BANK_FREE;
            end

            if (release_bank1_pulse_wr) begin
                if (bank1_state_wr == BANK_READY)
                    bank1_state_wr <= BANK_FREE;
            end

            // 提交当前帧
            if (capture_done && curr_bank_is_writing) begin
                if (wr_bank == 1'b0) begin
                    bank0_state_wr            <= BANK_READY;
                    frame_start_addr_bank0_wr <= frame_start_addr;
                    commit_tog_bank0_wr       <= ~commit_tog_bank0_wr;

                    if (other_bank_free_now) begin
                        bank1_state_wr <= BANK_WRITING;
                        wr_bank        <= 1'b1;
                        overflow       <= 1'b0;
                    end else begin
                        overflow       <= 1'b1;
                    end
                end else begin
                    bank1_state_wr            <= BANK_READY;
                    frame_start_addr_bank1_wr <= frame_start_addr;
                    commit_tog_bank1_wr       <= ~commit_tog_bank1_wr;

                    if (other_bank_free_now) begin
                        bank0_state_wr <= BANK_WRITING;
                        wr_bank        <= 1'b0;
                        overflow       <= 1'b0;
                    end else begin
                        overflow       <= 1'b1;
                    end
                end
            end
            // overflow 之后等待有空闲bank恢复写入
            else if (!curr_bank_is_writing) begin
                if (bank0_free_now_wr) begin
                    bank0_state_wr <= BANK_WRITING;
                    wr_bank        <= 1'b0;
                    overflow       <= 1'b0;
                end else if (bank1_free_now_wr) begin
                    bank1_state_wr <= BANK_WRITING;
                    wr_bank        <= 1'b1;
                    overflow       <= 1'b0;
                end
            end
        end
    end

    // ============================================================
    // 读域：同步commit toggle与每个bank的start_addr
    // ============================================================
    always @(posedge clk_read or negedge rst_n) begin
        if (!rst_n) begin
            commit0_rd_sync1 <= 1'b0;
            commit0_rd_sync2 <= 1'b0;
            commit0_rd_sync2_d <= 1'b0;

            commit1_rd_sync1 <= 1'b0;
            commit1_rd_sync2 <= 1'b0;
            commit1_rd_sync2_d <= 1'b0;

            frame_start_addr_bank0_rd_sync1 <= {ADDR_W{1'b0}};
            frame_start_addr_bank0_rd_sync2 <= {ADDR_W{1'b0}};
            frame_start_addr_bank1_rd_sync1 <= {ADDR_W{1'b0}};
            frame_start_addr_bank1_rd_sync2 <= {ADDR_W{1'b0}};
        end else begin
            commit0_rd_sync1   <= commit_tog_bank0_wr;
            commit0_rd_sync2   <= commit0_rd_sync1;
            commit0_rd_sync2_d <= commit0_rd_sync2;

            commit1_rd_sync1   <= commit_tog_bank1_wr;
            commit1_rd_sync2   <= commit1_rd_sync1;
            commit1_rd_sync2_d <= commit1_rd_sync2;

            frame_start_addr_bank0_rd_sync1 <= frame_start_addr_bank0_wr;
            frame_start_addr_bank0_rd_sync2 <= frame_start_addr_bank0_rd_sync1;

            frame_start_addr_bank1_rd_sync1 <= frame_start_addr_bank1_wr;
            frame_start_addr_bank1_rd_sync2 <= frame_start_addr_bank1_rd_sync1;
        end
    end

    // ============================================================
    //  读域：管理当前帧与挂起帧
    // ============================================================
    always @(posedge clk_read or negedge rst_n) begin
        if (!rst_n) begin
            frame_valid              <= 1'b0;
            active_bank_rd           <= 1'b0;
            active_frame_start_addr  <= {ADDR_W{1'b0}};

            pending_valid            <= 1'b0;
            pending_bank_rd          <= 1'b0;
            pending_frame_start_addr <= {ADDR_W{1'b0}};

            release_tog_bank0_rd     <= 1'b0;
            release_tog_bank1_rd     <= 1'b0;
        end else begin
            // 新完整帧到达
            if (commit_bank0_pulse_rd) begin
                if (!frame_valid) begin
                    frame_valid             <= 1'b1;
                    active_bank_rd          <= 1'b0;
                    active_frame_start_addr <= frame_start_addr_bank0_rd_sync2;
                end else if (active_bank_rd != 1'b0) begin
                    pending_valid            <= 1'b1;
                    pending_bank_rd          <= 1'b0;
                    pending_frame_start_addr <= frame_start_addr_bank0_rd_sync2;
                end
            end

            if (commit_bank1_pulse_rd) begin
                if (!frame_valid) begin
                    frame_valid             <= 1'b1;
                    active_bank_rd          <= 1'b1;
                    active_frame_start_addr <= frame_start_addr_bank1_rd_sync2;
                end else if (active_bank_rd != 1'b1) begin
                    pending_valid            <= 1'b1;
                    pending_bank_rd          <= 1'b1;
                    pending_frame_start_addr <= frame_start_addr_bank1_rd_sync2;
                end
            end

            // 当前帧读完
            if (rd_frame_done && frame_valid) begin
                if (active_bank_rd == 1'b0)
                    release_tog_bank0_rd <= ~release_tog_bank0_rd;
                else
                    release_tog_bank1_rd <= ~release_tog_bank1_rd;

                if (pending_valid) begin
                    frame_valid             <= 1'b1;
                    active_bank_rd          <= pending_bank_rd;
                    active_frame_start_addr <= pending_frame_start_addr;
                    pending_valid           <= 1'b0;
                end else begin
                    frame_valid <= 1'b0;
                end
            end
        end
    end

    // ============================================================
    // 读数据
    // 维持和原模块一致：raddr给出后，下一拍把当前active bank数据送出
    // ============================================================

//     always @(posedge clk_read or negedge rst_n) begin
//     if (!rst_n) begin
//         rdata_ch1 <= 8'd127;
//         rdata_ch2 <= 8'd127;
//         rdata_ch3 <= 8'd127;
//         rdata_ch4 <= 8'd127;
//     end else begin
//         rdata_ch1 <= bank0_rdata_b[7:0];
//         rdata_ch2 <= bank0_rdata_b[15:8];
//         rdata_ch3 <= bank0_rdata_b[23:16];
//         rdata_ch4 <= bank0_rdata_b[31:24];
//     end
// end
    always @(posedge clk_read or negedge rst_n) begin
        if (!rst_n) begin
            rdata_ch1 <= (1 << (DATA_W-1)) - 1;
            rdata_ch2 <= (1 << (DATA_W-1)) - 1;
            rdata_ch3 <= (1 << (DATA_W-1)) - 1;
            rdata_ch4 <= (1 << (DATA_W-1)) - 1;
        end else begin
            if (frame_valid) begin
                if (active_bank_rd == 1'b0) begin
                    rdata_ch1 <= bank0_rdata_b[7:0];
                    rdata_ch2 <= bank0_rdata_b[15:8];
                    rdata_ch3 <= bank0_rdata_b[23:16];
                    rdata_ch4 <= bank0_rdata_b[31:24];
                end else begin
                    rdata_ch1 <= bank1_rdata_b[7:0];
                    rdata_ch2 <= bank1_rdata_b[15:8];
                    rdata_ch3 <= bank1_rdata_b[23:16];
                    rdata_ch4 <= bank1_rdata_b[31:24];
                end
            end else begin
                rdata_ch1 <= (1 << (DATA_W-1)) - 1;
                rdata_ch2 <=(1 << (DATA_W-1)) - 1;
                rdata_ch3 <= (1 << (DATA_W-1)) - 1;
                rdata_ch4 <= (1 << (DATA_W-1)) - 1;
            end
        end
    end

endmodule
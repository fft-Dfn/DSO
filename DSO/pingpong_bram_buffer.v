module pingpong_bram_buffer #(
    parameter DATA_W = 8,
    parameter ADDR_W = 10
)(
    input  wire              rst_n,

    // =========================
    // 写口：采样域
    // =========================
    input  wire              clk_write,
    input  wire              we,
    input  wire [ADDR_W-1:0] waddr,
    input  wire [DATA_W-1:0] wdata_ch1,
    input  wire [DATA_W-1:0] wdata_ch2,
    input  wire [DATA_W-1:0] wdata_ch3,
    input  wire [DATA_W-1:0] wdata_ch4,
    input  wire              capture_done,
    input  wire [ADDR_W-1:0] frame_start_addr_in,

    // =========================
    // 读口：VGA域
    // 注意：同步读
    // raddr 在第 N 拍给出，rdata_ch1~4 在第 N+1 拍有效
    // =========================
    input  wire              clk_read,
    input  wire [ADDR_W-1:0] raddr,
    output wire [DATA_W-1:0] rdata_ch1,
    output wire [DATA_W-1:0] rdata_ch2,
    output wire [DATA_W-1:0] rdata_ch3,
    output wire [DATA_W-1:0] rdata_ch4,
    output reg  [ADDR_W-1:0] active_frame_start_addr,
    output reg               active_frame_valid,

    // =========================
    // 读口：Flash域
    // 注意：同步读
    // 当 flash_rd_en 在第 N 拍有效且给出 flash_raddr 时，
    // flash_rvalid 在第 N+1 拍拉高，同时 flash_rdata_ch1~4 有效
    // =========================
    input  wire              flash_rd_clk,
    input  wire              flash_rd_en,
    input  wire [ADDR_W-1:0] flash_raddr,
    output reg  [DATA_W-1:0] flash_rdata_ch1,
    output reg  [DATA_W-1:0] flash_rdata_ch2,
    output reg  [DATA_W-1:0] flash_rdata_ch3,
    output reg  [DATA_W-1:0] flash_rdata_ch4,
    output reg               flash_rvalid
);

    localparam TOTAL_DATA_W = DATA_W * 4;
    localparam TOTAL_ADDR_W = ADDR_W + 1;

    // 2 bank，4通道打包存储
    (* ram_style = "block" *) reg [TOTAL_DATA_W-1:0] ram_array [0:(1<<TOTAL_ADDR_W)-1];


    // 写时钟域：写采样数据、保存每帧起始地址、完成后翻 bank

    reg wr_bank;

    reg [ADDR_W-1:0] frame_start_bank0;
    reg [ADDR_W-1:0] frame_start_bank1;
    reg              bank0_valid;
    reg              bank1_valid;

    reg capture_done_d;
    wire capture_done_pulse;

    assign capture_done_pulse = capture_done & ~capture_done_d;

    always @(posedge clk_write or negedge rst_n) begin
        if (!rst_n) begin
            capture_done_d    <= 1'b0;
            wr_bank           <= 1'b0;
            frame_start_bank0 <= {ADDR_W{1'b0}};
            frame_start_bank1 <= {ADDR_W{1'b0}};
            bank0_valid       <= 1'b0;
            bank1_valid       <= 1'b0;
        end else begin
            // capture_done 上升沿检测
            capture_done_d <= capture_done;

            // 写当前采集 bank
            if (we) begin
                ram_array[{wr_bank, waddr}] <= {wdata_ch4, wdata_ch3, wdata_ch2, wdata_ch1};
            end

            // 一帧采完：记录该 bank 的 frame_start，然后切换写 bank
            if (capture_done_pulse) begin
                if (wr_bank == 1'b0) begin
                    frame_start_bank0 <= frame_start_addr_in;
                    bank0_valid       <= 1'b1;
                end else begin
                    frame_start_bank1 <= frame_start_addr_in;
                    bank1_valid       <= 1'b1;
                end

                wr_bank <= ~wr_bank;
            end
        end
    end


    // VGA 读时钟域
    // 读已经完成的一帧（非当前写 bank）

    reg wr_bank_sync1;
    reg wr_bank_sync2;
    reg wr_bank_sync2_d;

    wire rd_bank;
    wire rd_bank_change;

    reg [TOTAL_DATA_W-1:0] rdata_reg;

    assign rd_bank        = ~wr_bank_sync2;
    assign rd_bank_change = (wr_bank_sync2 != wr_bank_sync2_d);

    always @(posedge clk_read or negedge rst_n) begin
        if (!rst_n) begin
            wr_bank_sync1           <= 1'b0;
            wr_bank_sync2           <= 1'b0;
            wr_bank_sync2_d         <= 1'b0;
            rdata_reg               <= {TOTAL_DATA_W{1'b0}};
            active_frame_start_addr <= {ADDR_W{1'b0}};
            active_frame_valid      <= 1'b0;
        end else begin
            // 同步写 bank 到 VGA 读域
            wr_bank_sync1   <= wr_bank;
            wr_bank_sync2   <= wr_bank_sync1;
            wr_bank_sync2_d <= wr_bank_sync2;

            // 同步读 BRAM：地址给出后一拍数据有效
            rdata_reg <= ram_array[{rd_bank, raddr}];

            // 仅在 bank 切换时更新当前显示帧信息
            if (rd_bank_change) begin
                if (rd_bank == 1'b0) begin
                    active_frame_start_addr <= frame_start_bank0;
                    active_frame_valid      <= bank0_valid;
                end else begin
                    active_frame_start_addr <= frame_start_bank1;
                    active_frame_valid      <= bank1_valid;
                end
            end
        end
    end

    assign rdata_ch1 = rdata_reg[0*DATA_W +: DATA_W];
    assign rdata_ch2 = rdata_reg[1*DATA_W +: DATA_W];
    assign rdata_ch3 = rdata_reg[2*DATA_W +: DATA_W];
    assign rdata_ch4 = rdata_reg[3*DATA_W +: DATA_W];


    // Flash 读时钟域
    // 读已经完成的一帧（非当前写 bank）
    // flash_rd_en 第 N 拍有效 -> flash_rvalid 第 N+1 拍有效

    reg flash_bank_sync1;
    reg flash_bank_sync2;

    wire flash_rd_bank;

    reg [TOTAL_DATA_W-1:0] flash_rdata_bus;
    reg                    flash_rd_en_d;

    assign flash_rd_bank = ~flash_bank_sync2;

    always @(posedge flash_rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            flash_bank_sync1 <= 1'b0;
            flash_bank_sync2 <= 1'b0;
            flash_rdata_bus  <= {TOTAL_DATA_W{1'b0}};
            flash_rdata_ch1  <= {DATA_W{1'b0}};
            flash_rdata_ch2  <= {DATA_W{1'b0}};
            flash_rdata_ch3  <= {DATA_W{1'b0}};
            flash_rdata_ch4  <= {DATA_W{1'b0}};
            flash_rd_en_d    <= 1'b0;
            flash_rvalid     <= 1'b0;
        end else begin
            // 同步写 bank 到 Flash 读域
            flash_bank_sync1 <= wr_bank;
            flash_bank_sync2 <= flash_bank_sync1;

            // 第一级：发起 RAM 读
            if (flash_rd_en) begin
                flash_rdata_bus <= ram_array[{flash_rd_bank, flash_raddr}];
            end

            // 第二级：输出数据并给 valid
            flash_rd_en_d <= flash_rd_en;
            flash_rvalid  <= flash_rd_en_d;

            if (flash_rd_en_d) begin
                flash_rdata_ch1 <= flash_rdata_bus[0*DATA_W +: DATA_W];
                flash_rdata_ch2 <= flash_rdata_bus[1*DATA_W +: DATA_W];
                flash_rdata_ch3 <= flash_rdata_bus[2*DATA_W +: DATA_W];
                flash_rdata_ch4 <= flash_rdata_bus[3*DATA_W +: DATA_W];
            end
        end
    end

endmodule

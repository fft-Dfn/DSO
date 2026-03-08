module pingpong_bram_buffer #(
    parameter DATA_W = 8,
    parameter ADDR_W = 10
)(
    input  wire              rst_n,

    // ==========================================================
    // 写入域 (50MHz)
    // ==========================================================
    input  wire              clk_write,
    input  wire              we,            
    input  wire [ADDR_W-1:0] waddr,         
    input  wire [DATA_W-1:0] wdata_ch1,     
    input  wire [DATA_W-1:0] wdata_ch2,     
    input  wire [DATA_W-1:0] wdata_ch3,     
    input  wire [DATA_W-1:0] wdata_ch4,     
    input  wire              capture_done,

    // ==========================================================
    // 读取域 (VGA 像素时钟)
    // ==========================================================
    input  wire              clk_read,
    input  wire [ADDR_W-1:0] raddr,         
    output wire [DATA_W-1:0] rdata_ch1,     
    output wire [DATA_W-1:0] rdata_ch2,     
    output wire [DATA_W-1:0] rdata_ch3,     
    output wire [DATA_W-1:0] rdata_ch4      
);

    // 总线化聚合参数
    localparam TOTAL_DATA_W = DATA_W * 4;
    // 深度翻倍，最高位作为 Bank 选择
    localparam TOTAL_ADDR_W = ADDR_W + 1; 

    // -------------------------------------------------------------------------
    // 1. 物理存储阵列 (合并为单一 True Dual-Port BRAM 结构)
    // -------------------------------------------------------------------------
    (* ram_style = "block" *) reg [TOTAL_DATA_W-1:0] ram_array [0:(1<<TOTAL_ADDR_W)-1];

    // -------------------------------------------------------------------------
    // 2. Bank 状态机与翻转控制 (写入时钟域)
    // -------------------------------------------------------------------------
    reg wr_bank; 

    always @(posedge clk_write or negedge rst_n) begin
        if (!rst_n) begin
            wr_bank <= 1'b0;
        end else begin
            // capture_done 已是单脉冲，直接作为触发条件
            if (capture_done) begin
                wr_bank <= ~wr_bank;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 3. 跨时钟域同步 (CDC)
    // -------------------------------------------------------------------------
    reg wr_bank_sync1, wr_bank_sync2;
    always @(posedge clk_read or negedge rst_n) begin
        if (!rst_n) begin
            wr_bank_sync1 <= 1'b0;
            wr_bank_sync2 <= 1'b0;
        end else begin
            wr_bank_sync1 <= wr_bank;
            wr_bank_sync2 <= wr_bank_sync1;
        end
    end

    wire rd_bank = ~wr_bank_sync2;

    // -------------------------------------------------------------------------
    // 4. 地址映射与写入逻辑
    // -------------------------------------------------------------------------
    // 将 Bank 状态作为地址最高位，动态划分存储区
    wire [TOTAL_ADDR_W-1:0] mapped_waddr = {wr_bank, waddr};
    // 拼接 4 通道数据为 32-bit 总线
    wire [TOTAL_DATA_W-1:0] mapped_wdata = {wdata_ch4, wdata_ch3, wdata_ch2, wdata_ch1};

    always @(posedge clk_write) begin
        if (we) begin
            ram_array[mapped_waddr] <= mapped_wdata;
        end
    end

    // -------------------------------------------------------------------------
    // 5. 地址映射与读取逻辑
    // -------------------------------------------------------------------------
    wire [TOTAL_ADDR_W-1:0] mapped_raddr = {rd_bank, raddr};
    reg  [TOTAL_DATA_W-1:0] rdata_reg;

    always @(posedge clk_read) begin
        // 彻底消除组合逻辑 MUX，直接从映射地址读取单周期数据
        rdata_reg <= ram_array[mapped_raddr];
    end

    // 采用部分选择 (Part-Select) 语法精准拆解输出总线
    assign rdata_ch1 = rdata_reg[0*DATA_W +: DATA_W];
    assign rdata_ch2 = rdata_reg[1*DATA_W +: DATA_W];
    assign rdata_ch3 = rdata_reg[2*DATA_W +: DATA_W];
    assign rdata_ch4 = rdata_reg[3*DATA_W +: DATA_W];

endmodule
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
    input  wire                  capture_done, 
    input  wire                  we,
    output reg                   frame_valid,  // 读侧已有完整帧可读
    input  wire                  rd_frame_done, // 读侧声明：当前帧已经读完（读域脉冲）
    output reg                   overflow,//写侧数据溢出,当前完整帧提交时，没有空闲 bank 可切换，导致新帧吞吐跟不上
    input  wire [ADDR_W-1:0]     frame_start_addr,
    output reg  [ADDR_W-1:0]     active_frame_start_addr

);

  
    localparam DEPTH = (1 << ADDR_W);
    reg wr_bank;
    reg rd_bank;
  
    // 双 bank、四通道存储体
    (* ram_style = "block" *) reg [DATA_W-1:0] bank0_ch1 [0:DEPTH-1];
    (* ram_style = "block" *) reg [DATA_W-1:0] bank0_ch2 [0:DEPTH-1];
    (* ram_style = "block" *) reg [DATA_W-1:0] bank0_ch3 [0:DEPTH-1];
    (* ram_style = "block" *) reg [DATA_W-1:0] bank0_ch4 [0:DEPTH-1];

    (* ram_style = "block" *) reg [DATA_W-1:0] bank1_ch1 [0:DEPTH-1];
    (* ram_style = "block" *) reg [DATA_W-1:0] bank1_ch2 [0:DEPTH-1];
    (* ram_style = "block" *) reg [DATA_W-1:0] bank1_ch3 [0:DEPTH-1];
    (* ram_style = "block" *) reg [DATA_W-1:0] bank1_ch4 [0:DEPTH-1];

    // 写域状态
    // bank_full_wr[x] = 1 表示该 bank 已写完整帧，尚未被读侧释放
    reg [1:0] bank_full_wr;

    reg [ADDR_W-1:0] frame_start_addr_bank0_wr;
    reg [ADDR_W-1:0] frame_start_addr_bank1_wr;

    // 当前 wr_bank 是否可写
    wire curr_bank_full = (wr_bank == 1'b0) ? bank_full_wr[0] : bank_full_wr[1];

    wire write_allow = ~curr_bank_full;

    // 读域同步：同步bank_full到读域
    reg [1:0] bank_full_rd_sync1, bank_full_rd_sync2;
    reg [1:0] bank_full_rd_sync3;

    wire bank0_full_rd_rise;
    wire bank1_full_rd_rise;

    assign bank0_full_rd_rise =  bank_full_rd_sync2[0] & ~bank_full_rd_sync3[0];//上升沿往后推两个clk
    assign bank1_full_rd_rise =  bank_full_rd_sync2[1] & ~bank_full_rd_sync3[1];

    // 读域同步：同步 frame_start_addr 到读域
    // 这些元数据在 bank_full 置位后保持稳定，直到 bank 被释放重写
    // 所以可以用向量双触发同步，再配合同步后的 bank_full 使用
    reg [ADDR_W-1:0] frame_start_addr_bank0_rd_sync1, frame_start_addr_bank0_rd_sync2;
    reg [ADDR_W-1:0] frame_start_addr_bank1_rd_sync1, frame_start_addr_bank1_rd_sync2;

   //pending_valid：是否有等待切换的新帧
   //pending_bank：新帧在哪个 bank
   //pending_frame_start_addr：新帧的起始地址
   
    reg                  pending_valid;
    reg                  pending_bank;
    reg [ADDR_W-1:0]     pending_frame_start_addr;

    // 读完释放事件：读域 -> 写域
    // 每个bank各自一个 toggle
    reg release_tog_bank0_rd;
    reg release_tog_bank1_rd;

    reg release_tog_bank0_wr_sync1, release_tog_bank0_wr_sync2;
    reg release_tog_bank1_wr_sync1, release_tog_bank1_wr_sync2;

    reg release_tog_bank0_wr_sync3;
    reg release_tog_bank1_wr_sync3;

    wire release_bank0_pulse_wr;
    wire release_bank1_pulse_wr;

    assign release_bank0_pulse_wr = release_tog_bank0_wr_sync2 ^ release_tog_bank0_wr_sync3;
    assign release_bank1_pulse_wr = release_tog_bank1_wr_sync2 ^ release_tog_bank1_wr_sync3;

  
  

    // 写域：处理 bank 释放、写数据、提交新帧
    always @(posedge clk_write or negedge rst_n) begin
        if (!rst_n) begin
            wr_bank                  <= 1'b0;
            bank_full_wr             <= 2'b00;
            frame_start_addr_bank0_wr <= {ADDR_W{1'b0}};
            frame_start_addr_bank1_wr <= {ADDR_W{1'b0}};
            overflow                 <= 1'b0;

            release_tog_bank0_wr_sync1   <= 1'b0;
            release_tog_bank0_wr_sync2   <= 1'b0;
            release_tog_bank1_wr_sync1   <= 1'b0;
            release_tog_bank1_wr_sync2   <= 1'b0;
            release_tog_bank0_wr_sync3 <= 1'b0;
            release_tog_bank1_wr_sync3 <= 1'b0;
        end else begin
            // 先同步读侧的 release toggle
            release_tog_bank0_wr_sync1   <= release_tog_bank0_rd;
            release_tog_bank0_wr_sync2   <= release_tog_bank0_wr_sync1;
            release_tog_bank1_wr_sync1   <= release_tog_bank1_rd;
            release_tog_bank1_wr_sync2   <= release_tog_bank1_wr_sync1;

            release_tog_bank0_wr_sync3 <= release_tog_bank0_wr_sync2;
            release_tog_bank1_wr_sync3 <= release_tog_bank1_wr_sync2;

            // 收到读侧释放事件：清除对应 bank_full
            if (release_bank0_pulse_wr)
                bank_full_wr[0] <= 1'b0;

            if (release_bank1_pulse_wr)
                bank_full_wr[1] <= 1'b0;

        
            // 正常写数据：只允许写当前未 full 的 bank
            if (we && write_allow) begin
                if (wr_bank == 1'b0) begin
                    bank0_ch1[waddr] <= wdata_ch1;
                    bank0_ch2[waddr] <= wdata_ch2;
                    bank0_ch3[waddr] <= wdata_ch3;
                    bank0_ch4[waddr] <= wdata_ch4;
                end else begin
                    bank1_ch1[waddr] <= wdata_ch1;
                    bank1_ch2[waddr] <= wdata_ch2;
                    bank1_ch3[waddr] <= wdata_ch3;
                    bank1_ch4[waddr] <= wdata_ch4;
                end
            end

            // 当前帧写完：提交当前 wr_bank
            if (capture_done) begin
                if (wr_bank == 1'b0) begin
                    bank_full_wr[0]          <= 1'b1;
                    frame_start_addr_bank0_wr <= frame_start_addr;

                    // 尝试切去另一 bank
                    if (!bank_full_wr[1]) begin
                        wr_bank  <= 1'b1;
                    end else begin
                        // 两个 bank 都占着，没有空闲 bank 了
                        overflow <= 1'b1;
                    end
                end else begin
                    bank_full_wr[1]          <= 1'b1;
                    frame_start_addr_bank1_wr <= frame_start_addr;

                    if (!bank_full_wr[0]) begin
                        wr_bank  <= 1'b0;
                    end else begin
                        overflow <= 1'b1;
                    end
                end
            end
            // 一旦出现有空闲 bank，可清除 overflow
            if ((bank_full_wr != 2'b11) && !capture_done) begin
                overflow <= 1'b0;
            end
        end
    end

    // 读域：同步 bank_full 和 frame_start_addr
    always @(posedge clk_read or negedge rst_n) begin
        if (!rst_n) begin
            bank_full_rd_sync1   <= 2'b00;
            bank_full_rd_sync2   <= 2'b00;
            bank_full_rd_sync3 <= 2'b00;

            frame_start_addr_bank0_rd_sync1 <= {ADDR_W{1'b0}};
            frame_start_addr_bank0_rd_sync2 <= {ADDR_W{1'b0}};
            frame_start_addr_bank1_rd_sync1 <= {ADDR_W{1'b0}};
            frame_start_addr_bank1_rd_sync2 <= {ADDR_W{1'b0}};
        end else begin
            bank_full_rd_sync1   <= bank_full_wr;
            bank_full_rd_sync2   <= bank_full_rd_sync1;
            bank_full_rd_sync3 <= bank_full_rd_sync2;

            frame_start_addr_bank0_rd_sync1 <= frame_start_addr_bank0_wr;
            frame_start_addr_bank0_rd_sync2 <= frame_start_addr_bank0_rd_sync1;

            frame_start_addr_bank1_rd_sync1 <= frame_start_addr_bank1_wr;
            frame_start_addr_bank1_rd_sync2 <= frame_start_addr_bank1_rd_sync1;
        end
    end
    // 读域：管理 rd_bank / pending_bank / frame_valid / release
    always @(posedge clk_read or negedge rst_n) begin
        if (!rst_n) begin
            frame_valid              <= 1'b0;
            rd_bank              <= 1'b0;
            active_frame_start_addr  <= {ADDR_W{1'b0}};

            pending_valid            <= 1'b0;
            pending_bank             <= 1'b0;
            pending_frame_start_addr <= {ADDR_W{1'b0}};

            release_tog_bank0_rd     <= 1'b0;
            release_tog_bank1_rd     <= 1'b0;
        end else begin
            // 收到新完整帧（bank0）
            if (bank0_full_rd_rise) begin
                if (!frame_valid) begin
                    frame_valid             <= 1'b1;
                    rd_bank             <= 1'b0;
                    active_frame_start_addr <= frame_start_addr_bank0_rd_sync2;
                end else if (rd_bank != 1'b0) begin
                    pending_valid            <= 1'b1;
                    pending_bank             <= 1'b0;
                    pending_frame_start_addr <= frame_start_addr_bank0_rd_sync2;
                end
            end

            // 收到新完整帧（bank1）

            if (bank1_full_rd_rise) begin
                if (!frame_valid) begin
                    frame_valid             <= 1'b1;
                    rd_bank             <= 1'b1;
                    active_frame_start_addr <= frame_start_addr_bank1_rd_sync2;
                end else if (rd_bank != 1'b1) begin
                    pending_valid            <= 1'b1;
                    pending_bank             <= 1'b1;
                    pending_frame_start_addr <= frame_start_addr_bank1_rd_sync2;
                end
            end

            if (rd_frame_done && frame_valid) begin
                if (pending_valid) begin
            // 只有真正切换时，才释放旧 bank
                 if (rd_bank == 1'b0)
            release_tog_bank0_rd <= ~release_tog_bank0_rd;
                 else
            release_tog_bank1_rd <= ~release_tog_bank1_rd;

            // 切到新帧
             rd_bank             <= pending_bank;
             active_frame_start_addr <= pending_frame_start_addr;
             pending_valid           <= 1'b0;
             frame_valid             <= 1'b1;
            end else begin
        // 没有新帧：继续保持旧帧
        frame_valid             <= 1'b1;
        // rd_bank 不变
        // active_frame_start_addr 不变
        // 不发 release
            end
end
           
        end
    end

  
    // 读域：同步读当前 rd_bank
    // 注意：这里假定不会去读正在写的 bank
    // 由上面的协议保证这一点
    always @(posedge clk_read or negedge rst_n) begin
        if (!rst_n) begin
            rdata_ch1 <= {DATA_W{1'b0}};
            rdata_ch2 <= {DATA_W{1'b0}};
            rdata_ch3 <= {DATA_W{1'b0}};
            rdata_ch4 <= {DATA_W{1'b0}};
        end else begin
            if (frame_valid) begin
                if (rd_bank == 1'b0) begin
                    rdata_ch1 <= bank0_ch1[raddr];
                    rdata_ch2 <= bank0_ch2[raddr];
                    rdata_ch3 <= bank0_ch3[raddr];
                    rdata_ch4 <= bank0_ch4[raddr];
                end else begin
                    rdata_ch1 <= bank1_ch1[raddr];
                    rdata_ch2 <= bank1_ch2[raddr];
                    rdata_ch3 <= bank1_ch3[raddr];
                    rdata_ch4 <= bank1_ch4[raddr];
                end
            end else begin
                rdata_ch1 <= {DATA_W{1'b0}};
                rdata_ch2 <= {DATA_W{1'b0}};
                rdata_ch3 <= {DATA_W{1'b0}};
                rdata_ch4 <= {DATA_W{1'b0}};
            end
        end
    end

endmodule
module dds_generator #(
    parameter PHASE_W  = 32,  // 累加器位宽 (N)，决定频率分辨率
    parameter TABLE_AW = 8,   // 查找表地址位宽 (P)，决定存储深度
    parameter DATA_W   = 8    // 输出数据位宽 (D)，决定垂直分辨率
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // 关键：端口位宽现在完全随参数动态变化
    input  wire [PHASE_W-1:0]    freq_word,   
    input  wire [TABLE_AW-1:0]   phase_offset, 
    input  wire [1:0]            wave_type,

    output reg  [DATA_W-1:0]     wave_data
);

    // 计算截断起始位置
    localparam TRUNC_POS = PHASE_W - TABLE_AW;

    // 1. 相位累加器
    reg [PHASE_W-1:0] phase_acc;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) phase_acc <= {PHASE_W{1'b0}};
        else        phase_acc <= phase_acc + freq_word;
    end

    // 2. 相位截断与偏移
    wire [TABLE_AW-1:0] curr_phase;
    assign curr_phase = phase_acc[PHASE_W-1 : TRUNC_POS] + phase_offset;

    // 3. 查表 (ROM 的位宽也应参数化)
    wire [DATA_W-1:0] sin_out;
    sine_lut #(
        .ADDR_W(TABLE_AW), // 传递参数给下层模块
        .DATA_W(DATA_W)
    ) u_sine_lut (
        .clk  (clk),
        .addr (curr_phase),
        .data (sin_out)
    );

    // 4. 其他波形逻辑 (自动适配 DATA_W 和 TABLE_AW)
    wire [DATA_W-1:0] sqr_out = curr_phase[TABLE_AW-1] ? {DATA_W{1'b1}} : {DATA_W{1'b0}};
    wire [DATA_W-1:0] tri_out = curr_phase[TABLE_AW-1] ? 
                                (~curr_phase[TABLE_AW-2:0] << (DATA_W - (TABLE_AW-1))) : 
                                ( curr_phase[TABLE_AW-2:0] << (DATA_W - (TABLE_AW-1)));
    wire [DATA_W-1:0] saw_out = curr_phase << (DATA_W - TABLE_AW);

    // 5. 输出选择
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) wave_data <= {DATA_W{1'b0}};
        else begin
            case (wave_type)
                2'b00:   wave_data <= sin_out;
                2'b01:   wave_data <= sqr_out;
                2'b10:   wave_data <= tri_out;
                2'b11:   wave_data <= saw_out;
                default: wave_data <= {DATA_W{1'b0}};
            endcase
        end
    end
endmodule
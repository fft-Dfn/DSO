module waveform_renderer #(
    parameter H_ACTIVE = 640,
    parameter V_ACTIVE = 480
)(
    input  wire         de,
    input  wire [10:0]  pix_x,
    input  wire [9:0]   pix_y,

    input  wire         sample_valid,
    input  wire [7:0]   sample_ch1,
    input  wire [7:0]   sample_ch2,
    input  wire [7:0]   sample_ch3,
    input  wire [7:0]   sample_ch4,

    output reg  [15:0]  rgb565
);

    // RGB565颜色
    localparam [15:0] COLOR_BLACK   = 16'h0000;
    localparam [15:0] COLOR_GRID    = 16'h2104; // 深灰
    localparam [15:0] COLOR_CENTER  = 16'h39E7; // 亮灰
    localparam [15:0] COLOR_CH1     = 16'hF800; // 红
    localparam [15:0] COLOR_CH2     = 16'h07E0; // 绿
    localparam [15:0] COLOR_CH3     = 16'h001F; // 蓝
    localparam [15:0] COLOR_CH4     = 16'hFFE0; // 黄

    reg [9:0] y_ch1;
    reg [9:0] y_ch2;
    reg [9:0] y_ch3;
    reg [9:0] y_ch4;

    reg grid_hit;
    reg center_hit;
    reg ch1_hit, ch2_hit, ch3_hit, ch4_hit;

    always @(*) begin
        // 8bit采样映射到0~479
        y_ch1 = (V_ACTIVE - 1) - ((sample_ch1 * (V_ACTIVE - 1)) >> 8);
        y_ch2 = (V_ACTIVE - 1) - ((sample_ch2 * (V_ACTIVE - 1)) >> 8);
        y_ch3 = (V_ACTIVE - 1) - ((sample_ch3 * (V_ACTIVE - 1)) >> 8);
        y_ch4 = (V_ACTIVE - 1) - ((sample_ch4 * (V_ACTIVE - 1)) >> 8);

        // 每80列、每60行画网格
        grid_hit   = ((pix_x % 80) == 0) || ((pix_y % 60) == 0);
        center_hit = (pix_x == (H_ACTIVE >> 1)) || (pix_y == (V_ACTIVE >> 1));

        ch1_hit = sample_valid && ((pix_y >= y_ch1 - 1) && (pix_y <= y_ch1 + 1));
        ch2_hit = sample_valid && ((pix_y >= y_ch2 - 1) && (pix_y <= y_ch2 + 1));
        ch3_hit = sample_valid && ((pix_y >= y_ch3 - 1) && (pix_y <= y_ch3 + 1));
        ch4_hit = sample_valid && ((pix_y >= y_ch4 - 1) && (pix_y <= y_ch4 + 1));

        if (!de) begin
            rgb565 = COLOR_BLACK;
        end else if (ch1_hit) begin
            rgb565 = COLOR_CH1;
        end else if (ch2_hit) begin
            rgb565 = COLOR_CH2;
        end else if (ch3_hit) begin
            rgb565 = COLOR_CH3;
        end else if (ch4_hit) begin
            rgb565 = COLOR_CH4;
        end else if (center_hit) begin
            rgb565 = COLOR_CENTER;
        end else if (grid_hit) begin
            rgb565 = COLOR_GRID;
        end else begin
            rgb565 = COLOR_BLACK;
        end
    end

endmodule
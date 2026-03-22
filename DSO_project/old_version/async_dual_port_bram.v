// 异步双口 BRAM 模块（T20，替代 IP 核）
// 功能：双口异步读写，端口 A/B 独立时钟
// 所有读写操作在时钟上升沿触发
module async_dual_port_bram #(
    parameter DATA_W = 32,       // 数据宽度
    parameter ADDR_W = 10        // 地址宽度（2^ADDR_W 存储单元）
)(
    input  wire                 clk_a,   // 端口 A 时钟
    input  wire                 we_a,    // 端口 A 写使能
    input  wire [ADDR_W-1:0]   addr_a,  // 端口 A 地址
    input  wire [DATA_W-1:0]   wdata_a, // 端口 A 写数据
    output reg  [DATA_W-1:0]   rdata_a, // 端口 A 读数据

    input  wire                 clk_b,   // 端口 B 时钟
    input  wire                 we_b,    // 端口 B 写使能
    input  wire [ADDR_W-1:0]   addr_b,  // 端口 B 地址
    input  wire [DATA_W-1:0]   wdata_b, // 端口 B 写数据
    output reg  [DATA_W-1:0]   rdata_b  // 端口 B 读数据
);

    // 定义 BRAM 存储数组
    (* ram_style="block" *)
    reg [DATA_W-1:0] bram [(1<<ADDR_W)-1:0];

    // 端口 A 写/读逻辑
    always @(posedge clk_a) begin
        if (we_a)
            bram[addr_a] <= wdata_a;   // 写入数据
        rdata_a <= bram[addr_a];       // 读取数据（下一拍可用）
    end

    // 端口 B 写/读逻辑
    always @(posedge clk_b) begin
        if (we_b)
            bram[addr_b] <= wdata_b;   // 写入数据
        rdata_b <= bram[addr_b];       // 读取数据（下一拍可用）
    end

endmodule
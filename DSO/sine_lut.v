module sine_lut (
    input  wire       clk,
    input  wire [7:0] addr, // 256个地址
    output reg  [7:0] data  // 8位数据
);
    // 强制推断为 Efinix BRAM
    // 现在这个表只占用了 256 字节，极其微小
    (* rom_style = "block" *) reg [7:0] rom [0:255];

    initial begin
        $readmemh("sine_wave_256x8.hex", rom);
    end

    always @(posedge clk) data <= rom[addr];
endmodule
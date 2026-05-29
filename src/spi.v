module spi #(parameter CLK = 27000000)(clk, wr, data_in, data_out, fast, mosi, sclk, miso, busy);
input clk, wr, fast, miso;
input [7:0] data_in;
output mosi;
output busy, sclk;
output [7:0] data_out;

localparam SLOW_FREQ = 400000;
localparam SPI_DIV = $ceil($itor(CLK) / (2 * SLOW_FREQ));
// fast freq. is CLK / 2

reg [5:0] divcnt = 0;
reg [7:0] send = 'hff;
reg [8:0] recv = 0;
reg busy = 0, sclk = 0;
assign data_out = recv[7:0];
assign mosi = send[7];
always @(posedge clk) begin
	if (wr & ~busy) begin
		send <= data_in;
		recv <= 1;
		busy <= 1;
		divcnt <= fast ? 6'b0 : SPI_DIV - 1'b1;
	end
	else if (busy)
		if (|divcnt) divcnt <= divcnt - 1'b1;
		else begin
			if (sclk) send <= { send[6:0], 1'b1 };
			if (~sclk) recv <= { recv[7:0], miso };
			if (recv[8] & sclk) busy <= 0;
			divcnt <= fast ? 6'b0 : SPI_DIV - 1'b1;
			sclk <= ~sclk;
		end
end

endmodule

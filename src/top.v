module top(I_clk, lcd_rst_n, lcd_cs_n, lcd_a0, sck, sda);
input I_clk;
output sck, sda;
output lcd_rst_n, lcd_cs_n, lcd_a0;

function [7:0] sel4x8;
	input [1:0] sel;
	input [31:0] a;
	begin
		case (sel)
			2'b00: sel4x8 = a[7:0];
			2'b01: sel4x8 = a[15:8];
			2'b10: sel4x8 = a[23:16];
			2'b11: sel4x8 = a[31:24];
		endcase
	end
endfunction

wire [15:0] pc, adr, data_out;

wire [13:0] iadr = pc[15:2];
wire [13:0] iadr1 = pc[1] ? iadr + 1'b1 : iadr;
wire [31:0] insn;

wire [13:0] dadr = adr[15:2];
wire [5:0] dadr_next_l = dadr[5:0] + 1'b1; // wrap-around
wire [13:0] dadr0 = { dadr[13:6], &adr[1:0] ? dadr_next_l : dadr[5:0] };

wire wr_l, wr_u;
wire we0 = wr_l & adr[1:0] == 2'b00 | wr_u & adr[1:0] == 2'b11;
wire we1 = wr_l & adr[1:0] == 2'b01 | wr_u & adr[1:0] == 2'b00;
wire we2 = wr_l & adr[1:0] == 2'b10 | wr_u & adr[1:0] == 2'b01;
wire we3 = wr_l & adr[1:0] == 2'b11 | wr_u & adr[1:0] == 2'b10;

wire [7:0] dl = data_out[7:0], du = data_out[15:8];
wire [7:0] ramd0, ramd1, ramd2, ramd3;

reg [1:0] sel_adr;
always @(posedge clk)
	sel_adr <= adr[1:0];

reg [2:0] vrtc;
always @(posedge clk)
	vrtc <= { lcd_cs_n, vrtc[2:1] };

wire [15:0] data_in = {
	sel4x8(sel_adr, { ramd0, ramd3, ramd2, ramd1 }),
	sel4x8(sel_adr, { ramd3, ramd2, ramd1, ramd0 })
};

ram #(.FILE("ram0.mem"))
	ram0(.clk(clk), .ada(iadr1), .douta(insn[7:0]),
	.adb(dadr0), .dinb(adr[0] ? du : dl), .doutb(ramd0), .wreb(we0));
ram #(.FILE("ram1.mem"))
	ram1(.clk(clk), .ada(iadr1), .douta(insn[15:8]),
	.adb(dadr),  .dinb(adr[0] ? dl : du), .doutb(ramd1), .wreb(we1));
ram #(.FILE("ram2.mem"))
	ram2(.clk(clk), .ada(iadr), .douta(insn[23:16]),
	.adb(dadr),  .dinb(adr[0] ? du : dl), .doutb(ramd2), .wreb(we2));
ram #(.FILE("ram3.mem"))
	ram3(.clk(clk), .ada(iadr), .douta(insn[31:24]),
	.adb(dadr),  .dinb(adr[0] ? dl : du), .doutb(ramd3), .wreb(we3));

reg intreq;
wire intack, rst_n;
always @(posedge clk)
	if (~rst_n) intreq <= 1'b0;
	else if (intack) intreq <= 1'b0;
	else if (vrtc[1:0] == 2'b10) intreq <= 1'b1;

f6502wide cpu(.clk(clk), .reset(~rst_n), .pc_out(pc), .insn_in(insn),
	.adr_out(adr), .data_in(data_in), .data_out(data_out),
	.wr_l(wr_l), .wr_u(wr_u),
	.intreq(intreq), .intack(intack), .nmireq(1'b0), .nmiack());

reg [7:0] vram0[0:'h7ff], vram1[0:'h7ff];
always @(posedge clk) begin
	if ((adr[0] ? wr_u : wr_l) & &adr[15:12])
		vram0[adr[11:1] + adr[0]] <= 
			adr[0] ? data_out[15:8] : data_out[7:0];
	if ((adr[0] ? wr_l : wr_u) & &adr[15:12])
		vram1[adr[11:1]] <=
			adr[0] ? data_out[7:0] : data_out[15:8];
end
reg [7:0] vramadr_l, vramout;
reg [3:0] vramadr_u;
wire [11:0] vramadr = { vramadr_u, vramadr_l };
always @(posedge c_clk)
	vramout <= vramadr_l[0] ? vram1[vramadr[11:1]] : vram0[vramadr[11:1]];

reg trans_start;
reg [4:0] start_adr = 0;
always @(posedge clk)
	if (vrtc[1:0] == 2'b01) trans_start <= 0;
	else if (wr_l & adr == 'heff1) begin
		start_adr <= data_out[4:0];
		trans_start <= 1;
	end

localparam SYSCLK = 68750000;
pll pll(.clkin(I_clk), .mdclk(I_clk), .clkout0(clk), .clkout1(c_clk), .lock(lock));
reg [17:0] lockcnt = 0;
assign rst_n = lockcnt[17]; // >2mS
always @(posedge clk)
	if (~lock) lockcnt <= 0;
	else if (~rst_n) lockcnt <= lockcnt + 1'b1;

wire [2:0] port;
wire [7:0] port_out;

f1802 f1802(.clk(c_clk), .reset(~rst_n),
	.ef({ 1'b0, trans_start, timer_active, spi_busy }), .q(lcd_a0),
	.iord(), .iowr(c_iowr), .port(port),
	.port_in(port[0] ? vramout : start_adr), .port_out(port_out));

spi #(.CLK(SYSCLK))
	spi(.clk(c_clk), .wr(c_iowr & port == 1), .fast(1'b1),
	.data_in(port_out), .data_out(), .busy(spi_busy),
	.mosi(sda), .sclk(sck), .miso(1'b1));

timer #(.CLK(SYSCLK))
	timer(.clk(c_clk), .wr(c_iowr & port == 3), .active(timer_active));

reg lcd_rst_n, lcd_cs_n;
always @(posedge c_clk)
	if (c_iowr)
		case (port)
			2: { lcd_rst_n, lcd_cs_n } <= port_out[1:0];
			4: vramadr_l <= port_out;
			5: vramadr_u <= port_out[3:0];
		endcase

endmodule

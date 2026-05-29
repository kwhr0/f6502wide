// f1802
// Copyright 2026 © Yasuo Kuwahara

// MIT License

// not implemented: interrupt,DMA (IDL,SAV,MARK,RET,DIS)

module f1802(clk, reset, ef, iord, iowr, q, port, port_in, port_out);
input clk, reset;
input [3:0] ef;
input [7:0] port_in;
output iord, iowr, q;
output [2:0] port;
output [7:0] port_out;

localparam ADRMSB = 10;

localparam F = 0;
localparam E = 1;
localparam B = 2;

reg [2:0] s = 0;
reg [3:0] p = 0, x;
reg [7:0] d;
reg df, q = 0;

wire [3:0] i = dout[7:4], n = dout[3:0];
wire io = i == 4'b0110;
wire i7 = i == 4'b0111;
wire plo = i == 4'b1010;
wire phi = i == 4'b1011;
wire long = i == 4'b1100;

always @(posedge clk)
	if (reset) s <= 0;
	else s <= { s[1] & long, s[0], s[1] & ~long | s[2] | ~|s };
always @(posedge clk)
	if (s[E]) begin
		if (i == 4'b1101) p <= n;
		if (i == 4'b1110) x <= n;
		if (i7 & n[3:1] == 3'b101) q <= n[0];
	end

// MEMORY

wire [15:0] adr;
reg [7:0] ram[0:2**(ADRMSB+1)-1];
initial $readmemh("ram.mem", ram);
wire [7:0] din = _input ? port_in : d;
wire memw = s[E] & (i == 4'b0101 | _input | i7 & n == 4'b0011);
reg [7:0] dout;
always @(posedge clk) begin
	if (memw) begin
		ram[adr[ADRMSB:0]] <= din;
		dout <= din;
	end
	else dout <= ram[adr[ADRMSB:0]];
end

// REGISTER

reg [7:0] rl[0:15], ru[0:15];
wire inc_long = long & (~n[2] | ~cond_ok);
reg inc_long1;
reg [7:0] dout1;
always @(posedge clk) begin
	inc_long1 <= s[E] & inc_long;
	if (s[B]) dout1 <= dout;
end
wire [31:0] inc_lut = 32'h001a005a, inc7_lut = 32'hbf00b004;
wire inc = inc_lut[{ n[3], i }] | &i[2:0] & inc7_lut[{ i[3], n }];
wire dec = s[E] & (i == 4'b0010 | i7 & n == 4'b0011);
wire regen = s[F] | s[E] & (inc | dec | inc_long) | s[B] & inc_long1;
wire [15:0] adr_next = adr + { {15{ dec }}, 1'b1 };
wire sel_x = io | &i[2:0] & ~n[3];
wire [15:0] sel_n_lut = 16'h0f37;
wire [3:0] regnum = s[E] & sel_n_lut[i] ? n : s[E] & sel_x ? x : p;
always @(posedge clk) begin
	if (regen | s[E] & plo)
		rl[regnum] <= regen ? adr_next[7:0] : d;
	if (regen | s[E] & phi)
		ru[regnum] <= regen ? adr_next[15:8] : d;
end
wire [7:0] reg_u = ru[regnum], reg_l = rl[regnum];

// PC

wire [7:0] conds = { ef, df, ~|d, q, 1'b1 };
wire cond_ok = n[3] ^ conds[{ i[0] & n[2], n[1:0] }];
reg sel_adr_l, sel_adr_u, jmp;
always @(posedge clk) begin
	jmp <= s[E] & cond_ok & ~n[2];
	sel_adr_u <= s[B] & jmp;
	sel_adr_l <= s[B] & jmp | s[E] & cond_ok & i == 4'b0011;
end
assign adr = { sel_adr_u ? dout1 : reg_u, sel_adr_l ? dout : reg_l };

// DATA

reg [1:0] sel_logic;
reg [2:0] sel_alu;
reg [7:0] reg_y;
reg sub_a, sub_b, cy, d_en, df_en, sft, sft_df;
wire [15:0] d_en_lut = 16'h8311, d_en7_lut = 16'hf0f4;
always @(posedge clk) begin
	sel_logic <= {2{ i[3] }} & n[1:0];
	sub_a <= &n[1:0];
	sub_b <= ^n[1:0];
	cy <= |n[1:0] ? df | i[3] : df & ~i[3];
	sel_alu <= { &i[2:0] & n[2] & n[1:0] != 2'b10,
		_input, i[3:2] == 2'b10 | i[1] & n[2] };
	d_en <= s[E] & (d_en_lut[i] | i7 & d_en7_lut[n] | _input);
	df_en <= s[E] & &i[2:0] & n[2];
	sft <= n[1:0] == 2'b10;
	sft_df <= n[3] ? d[7] : d[0];
	reg_y <= i[1] ?
		n[3] ? { d[6:0], df & ~i[3] } : { df & ~i[3], d[7:1] } :
		i[0] ? reg_u : reg_l;
end
wire [7:0] logic_y = sel_logic[1] ?
	sel_logic[0] ? dout ^ d : dout & d :
	sel_logic[0] ? dout | d : dout;
wire [8:0] add_y = { dout ^ {8{ sub_a }} } + { d ^ {8{ sub_b }} } + cy;
wire [7:0] alu_y = sel_alu[2] ? add_y[7:0] :
	sel_alu[1] ? port_in : sel_alu[0] ? reg_y : logic_y;
always @(posedge clk) begin
	if (d_en) d <= alu_y;
	if (df_en) df <= sft ? sft_df : add_y[8];
end

// I/O

wire _input = io & n >= 9;
wire _output = io & n >= 1 & n <= 7;
reg iowr;
reg [2:0] port1;
always @(posedge clk) begin
	if (s[E]) port1 <= n[2:0];
	iowr <= s[E] & _output;
end
assign iord = s[E] & _input;
assign port = iord ? n[2:0] : port1;
assign port_out = dout;

integer c;
initial for (c = 0; c <= 15; c = c + 1) begin
	ru[c] = 0;
	rl[c] = 0;
end

wire [7:0] lc = s[E] & plo ? "L" : s[E] & phi ? "H" : " ";
wire [7:0] wc = memw ? "S" : " ";
initial $monitor("%x %x %c %x %x %c %x %x",
	s, regnum, lc, d, adr, wc, din, dout);
endmodule

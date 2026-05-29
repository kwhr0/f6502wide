// 6502 MPU binary compatible soft core
// 32-bit instruction bus & 16-bit data bus
// Copyright 2026 © Yasuo Kuwahara

// MIT License

// not implemented: decimal ADC/SBC (D flag ignored)

module f6502wide(clk, reset, pc_out, insn_in, adr_out,
	data_in, data_out, wr_l, wr_u, intreq, intack, nmireq, nmiack);
input clk, reset, intreq, nmireq;
input [31:0] insn_in;
input [15:0] data_in;
output [15:0] pc_out, adr_out, data_out;
output wr_l, wr_u, intack, nmiack;

localparam C = 0;
localparam Z = 1;
localparam I = 2;
localparam B = 4;
localparam V = 6;
localparam N = 7;

reg [7:0] a, x, y, sp, psr;
reg [15:0] pc;

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

//
// DECODE
//

wire [7:0] o = force_nop ? 8'hea : sel4x8(pc[1:0], insn_in);
wire [23:0] insn = {
	sel4x8(pc[1:0], { insn_in[15:0], insn_in[31:16] }),
	sel4x8(pc[1:0], { insn_in[7:0], insn_in[31:8] }),
	o
};

localparam BIT = 0;
localparam TAX = 1;
localparam TAY = 2;
localparam TSX = 3;
localparam TXS = 4;
localparam RTS = 5;
localparam I1MAX = 5;
//
localparam CLCSEC = 6;
localparam CLDSED = 7;
localparam CLISEI = 8;
localparam DEX = 9;
localparam DEY = 10;
localparam INX = 11;
localparam INY = 12;
localparam JMP = 13;
localparam JSR = 14;
localparam LDXLDY = 15;
localparam PH = 16;
localparam PL = 17;
localparam RTI = 18;
localparam IMAX = 18;

wire [IMAX:0] i;
assign i[PH] = ~o[7] & o[5:0] == 6'b001000;
assign i[PL] = ~o[7] & o[5:0] == 6'b101000;
assign i[JMP] = o[7:6] == 2'b01 & o[4:0] == 5'b01100;
assign i[CLCSEC] = o[7:6] == 2'b00 & o[4:0] == 5'b11000;
assign i[CLISEI] = o[7:6] == 2'b01 & o[4:0] == 5'b11000;
assign i[CLDSED] = o[7:6] == 2'b11 & o[4:0] == 5'b11000;
assign i[LDXLDY] = o[7:5] == 3'b101 &
	(~|o[4:3] | o[4:2] == 3'b011 | o[4] & o[2]) & ~o[0];
assign i[BIT] = o[7:4] == 4'b0010 & o[2:0] == 3'b100;
assign i[JSR] = o == 8'h20;
assign i[RTI] = o == 8'h40;
assign i[RTS] = o == 8'h60;
assign i[DEY] = o == 8'h88;
assign i[TXS] = o == 8'h9a;
assign i[TAY] = o == 8'ha8;
assign i[TAX] = o == 8'haa;
assign i[TSX] = o == 8'hba;
assign i[INY] = o == 8'hc8;
assign i[DEX] = o == 8'hca;
assign i[INX] = o == 8'he8;

// instruction byte count

wire byte1 = ~o[7] & o[6:5] != 2'b01 & ~|o[4:0] |
	o[3:2] == 2'b10 & (o[1] | ~o[0]);
wire byte3 = o == 8'h20 | o[4:0] == 5'b11001 | &o[3:2] & ~&o[1:0];
wire [1:0] bytes = { ~byte1 | byte3, byte1 | byte3 };

// state

wire dbl_state = o[7:6] != 2'b10 & o[2:0] == 3'b110; // read modify write
reg state;
always @(posedge clk)
	if (reset | state) state <= 1'b0;
	else if (dbl_state) state <= 1'b1;

// interrupt

reg isbrk;
reg [1:0] vect, rcnt, wcnt;
wire accept = active & ~(dbl_state & ~state) & ~i[RTS] & ~i[RTI];
wire valid_intr = intreq & ~psr[I] | nmireq;
wire wcnt_dbl = wcnt == 1;
wire wcnt_sngl = wcnt == 2;
always @(posedge clk)
	if (reset) rcnt <= 0;
	else if (|rcnt) rcnt <= rcnt - 1'b1;
	else if (i[RTI]) rcnt <= 2; // start pull
always @(posedge clk)
	if (reset) begin
		wcnt <= 0;
		vect <= 2;
	end
	else if (wcnt[1]) wcnt <= 0;
	else if (wcnt[0]) wcnt <= 2;
	else if (accept & (valid_intr | ~|o)) begin
		wcnt <= 1; // start push
		vect <= { ~nmireq, 1'b1 };
		isbrk <= ~valid_intr;
	end
assign intack = vect[1] & |wcnt;
assign nmiack = ~vect[1] & |wcnt;

reg [2:0] active_sr;
always @(posedge clk)
	if (reset | wcnt_sngl) active_sr <= 0;
	else active_sr <= { active_sr[1:0], 1'b1 };
wire active = active_sr[2];

// EA

wire xysel = o[4] & (~o[2] | o[7:6] == 2'b10 & o[1:0] == 2'b10);
wire [7:0] xy = xysel ? fwd_y : fwd_x;
wire xymask = (o[4] ~^ |o[3:2]) & (o[7] | |o[1:0]);
wire [15:0] xyofs = insn[23:8] + (xy & {8{ xymask }});
wire umask = &o[4:3] | &o[3:2] | ~o[7] & ~|o[1:0];
wire [15:0] ea = { xyofs[15:8] & {8{ umask }}, xyofs[7:0] };

wire t_ind = o[3:0] == 4'b0001 | i[JMP] & o[5];
reg ind1;
always @(posedge clk)
	ind1 <= ~ind1 & t_ind;
wire ind = t_ind & ~ind1;

// PC

reg exec_ret1;
always @(posedge clk)
	if (reset) exec_ret1 <= 0;
	else exec_ret1 <= i[RTS] | i[RTI] & rcnt == 2;
wire force_nop = ~active | exec_ret1 | |wcnt;
wire [3:0] cond = { fwd_psr[Z], fwd_psr[C], fwd_psr[V], fwd_psr[N] };
wire cond_ok = cond[o[7:6]] ~^ o[5];
wire [15:0] nextpc_normal = pc + bytes;
wire [15:0] nextpc_rel = nextpc_normal + { {8{ insn[15] }}, insn[15:8] };
wire [15:0] nextpc = o[4:0] == 5'b10000 & cond_ok ? nextpc_rel :
	i[JMP] & o[5] & ind1 | exec_ret1 ? data_in + i1[RTS] :
	i[JMP] & ~o[5] | i[JSR] ? ea :
	nextpc_normal;

assign pc_out = active & ~(dbl_state & ~state) &
	~|wcnt & (~i[RTI] | rcnt == 1) & ~ind ? nextpc : pc;

always @(posedge clk)
	pc <= active ? pc_out : data_in;

// address selector

wire [7:0] sp_adr = fwd_sp + { {7{ i[JSR] | wcnt_dbl }},
	i[PL] | i[JSR] | i[RTS] | i[RTI] | wcnt_dbl };
assign adr_out = active ?
	i[PH] | i[PL] | i[JSR] | i[RTS] | |wcnt | i[RTI] ? { 8'h01, sp_adr } :
	ind1 ? data_in + (fwd_y & {8{ o1[4] }}) : ea :
	{ 13'b1111_1111_1111_1, vect, 1'b0 };

// write data (write only)

wire [7:0] wd8 = o[2] & ~o[0] ?
	o[1] & ~wcnt_sngl ? fwd_x : fwd_y :
	|o[7:6] & ~wcnt_sngl ? fwd_a : fwd_psr;
wire [15:0] wd16 = pc + { ~|wcnt, 1'b0 };
wire wr_s0_u = ~state & ~ind & i[JSR] | wcnt_dbl;
wire wr_s0_l = ~state & ~ind &
	(i[PH] | o[7:5] == 3'b100 & (o[0] ? ~o[1] : o[2])) | wcnt_sngl;
wire [15:0] wd_s0 = { wd16[15:8], wr_s0_u ? wd16[7:0] : wd8 };

//
// EXEC
//

reg [7:0] imm1, o1;
reg [I1MAX:0] i1;
reg sel_alu_a, sel_alu_xy, sel_alu_b, a_and, a_or, b_and, b_xor, t_add_c;
reg dbl_state1, sel_logic_eoror, sel_logic_and, sel_add, sel_sft;
always @(posedge clk) begin
	imm1 <= insn[15:8];
	i1 <= i[I1MAX:0];
	o1 <= o;
	dbl_state1 <= dbl_state;
	sel_alu_a <= o[6:5] == 2'b01 | o[0];
	sel_alu_xy <= ~o[5] & ~|o[1:0];
	sel_alu_b <= ~o[2] & (o[0] ? o[4:3] == 2'b01 : ~o[3]);
	a_and <= o[2:0] != 3'b110;
	a_or <= o[7:5] == 3'b110 & o[2:0] == 3'b110;
	b_and <= ~(o[3:2] == 2'b10 & ~o[0]);
	b_xor <= o[7] & o[1:0] == 2'b01 | o[3:2] != 2'b10 & ~|o[1:0] |
		~|o[6:4] & ~o[1] | o[6:5] == 2'b10 & o[2:1] == 2'b01;
	t_add_c <= o[6] & ~|o[1:0] | ~o[5] & o[0] | &o[6:5] & ~o[0];
	sel_logic_eoror <= ~o[7] & ~o[5];
	sel_logic_and <= o[7:5] == 3'b001 & |o[2:0];
	sel_add <= o[7] & (o[6] | o[3:2] == 2'b10 & ~o[0]) |
		o[7:5] == 3'b011 & o[1:0] == 2'b01;
	sel_sft <= ~o[7] & o[1:0] == 2'b10;
end

wire [7:0] alu_a = sel_alu_a ? a : sel_alu_xy ? y : x;
wire [7:0] alu_b = sel_alu_b ? imm1 : data_in[7:0];
wire [7:0] add_a = alu_a & {8{ a_and }} | {8{ a_or }};
wire [7:0] add_b = alu_b & {8{ b_and }} ^ {8{ b_xor }};
wire add_c = psr[C] & o1[0] | t_add_c;
wire [8:0] add_y = add_a + add_b + add_c;
wire [7:0] sft_a = o1[2] ? data_in[7:0] : a;
wire [7:0] sft_y = o1[6] ? { psr[C] & o1[5], sft_a[7:1] } :
	{ sft_a[6:0], psr[C] & o1[5] };
wire [7:0] logic_y = sel_logic_eoror ?
	o1[6] ? a ^ alu_b : a | alu_b :
	sel_logic_and ? a & alu_b : alu_b;
wire [7:0] alu_y = sel_add ? add_y[7:0] : sel_sft ? sft_y : logic_y;

// write data (after read)

reg t_wr_s1_l;
always @(posedge clk)
	t_wr_s1_l <= dbl_state;
wire wr_s1_l = state & t_wr_s1_l;
assign wr_u = wr_s0_u;
assign wr_l = wr_s0_l | wr_s1_l | wr_s0_u;
assign data_out = wr_s1_l ? { 8'h00, alu_y } : wd_s0;

//
// UPDATE
//

wire ren = ~dbl_state1 | state;

// A register

reg load_a1;
always @(posedge clk)
	load_a1 <= ~ind & (~o[7] & o[3:0] == 4'b1010 |
		{ o[7], o[5] } != 2'b10 & o[1:0] == 2'b01 |
		i[PL] & o[6] | o == 8'h8a | o == 8'h98);
wire [7:0] fwd_a = load_a1 ? alu_y : a;
always @(posedge clk)
	if (ren & load_a1) a <= fwd_a;

// X register

reg [1:0] x_add1;
reg sel_x1, load_x1;
always @(posedge clk) begin
	x_add1 <= { i[DEX], i[DEX] | i[INX] };
	sel_x1 <= i[LDXLDY] & o[1] | i[TAX] | i[TSX];
	load_x1 <= ~ind &
		(i[LDXLDY] & o[1] | i[INX] | i[DEX] | i[TAX] | i[TSX]);
end

wire [7:0] x_add = x + { {6{ x_add1[1] }}, x_add1 };
wire [7:0] x_sel = i1[TAX] ? a : i1[TSX] ? sp : alu_b;
wire [7:0] fwd_x = sel_x1 ? x_sel : x_add;
always @(posedge clk)
	if (ren & load_x1) x <= fwd_x;

// Y register

reg [1:0] y_add1;
reg sel_y1, load_y1;
always @(posedge clk) begin
	y_add1 <= { i[DEY], i[DEY] | i[INY] };
	sel_y1 <= i[LDXLDY] & ~o[1] | i[TAY];
	load_y1 <= ~ind &
		(i[LDXLDY] & ~o[1] | i[INY] | i[DEY] | i[TAY]);
end

wire [7:0] y_add = y + { {6{ y_add1[1] }}, y_add1 };
wire [7:0] y_sel = i1[TAY] ? a : alu_b;
wire [7:0] fwd_y = sel_y1 ? y_sel : y_add;
always @(posedge clk)
	if (ren & load_y1) y <= fwd_y;

// SP register

reg load_sp1;
reg [2:0] sp_add1;
wire sp_plus1 = i[PL] | i[RTI] & ~|rcnt;
wire sp_plus2 = i[RTS] | rcnt == 1;
wire sp_minus1 = i[PH] | wcnt_sngl;
wire sp_minus2 = i[JSR] | wcnt_dbl;
always @(posedge clk) begin
	load_sp1 <= ~ind &
		(i[TXS] | sp_plus1 | sp_plus2 | sp_minus1 | sp_minus2);
	sp_add1 <= { sp_minus1 | sp_minus2, ~sp_plus1, sp_plus1 | sp_minus1 };
end
wire [7:0] fwd_sp = load_sp1 ?
	i1[TXS] ? x : sp + { {5{ sp_add1[2] }}, sp_add1 } :
	sp;
always @(posedge clk)
	if (reset) sp <= 0;
	else if (ren & load_sp1) sp <= fwd_sp;

// PSR register

wire [63:0] zlut0 = 64'h0f0f_af44_0400_0a00;
wire [15:0] zlut2 = 16'h1d55;
wire calu = (o[7:5] == 3'b011 | &o[7:6]) & o[1:0] == 2'b01 |
	&o[7:6] & ~o[4] & o[3:2] != 2'b10 & ~|o[1:0];
wire csft = ~o[7] & (o[2:0] == 3'b110 | ~o[4] & o[3:0] == 4'b1010);
wire zn = o[1] ?
	o[3:2] == 2'b10 ? zlut2[o[7:4]] : o[7:5] != 3'b100 :
	o[0] ? o[7:5] != 3'b100 : zlut0[o[7:2]];
wire vof = &o[6:5] & o[1:0] == 2'b01;

reg plp1, calu1, csft1, c1_1, t_i, t_d;
always @(posedge clk) begin
	plp1 <= ~ind & i[PL] & ~o[6];
	calu1 <= calu;
	csft1 <= csft;
	c1_1 <= i[CLCSEC] & o[5];
	t_i <= i[CLISEI] & o[5] | wcnt_sngl;
	t_d <= i[CLDSED] & o[5];
end

wire t_c = calu1 & add_y[8] | csft1 & (o1[6] ? sft_a[0] : sft_a[7]) | c1_1;
wire t_z = ~|alu_y[7:0];
wire t_v = i1[BIT] ? data_in[6] :
	add_a[7] & add_b[7] & ~add_y[7] | ~add_a[7] & ~add_b[7] & add_y[7];
wire t_n = i1[BIT] ? data_in[7] : alu_y[7];

reg update_c, update_zn, update_i, update_d, update_b, update_v;
always @(posedge clk) begin
	update_c <= ~ind & (calu | csft | i[CLCSEC]);
	update_zn <= ~ind & zn;
	update_i <= ~ind & (i[CLISEI] | wcnt_sngl);
	update_d <= ~ind & i[CLDSED];
	update_b <= ~ind & wcnt_sngl;
	update_v <= ~ind & (vof | i1[BIT] | o == 8'hb8);
end

wire [7:0] fwd_psr = plp1 | rcnt == 2 ? data_in[7:0] : {
	ren & update_zn ? t_n : psr[7],
	ren & update_v ? t_v : psr[6],
	1'b1,
	ren & update_b ? isbrk : psr[4],
	ren & update_d ? t_d : psr[3],
	ren & update_i ? t_i : psr[2],
	ren & update_zn ? t_z : psr[1],
	ren & update_c ? t_c : psr[0]
};
always @(posedge clk)
	if (reset) psr <= 1 << I;
	else psr <= fwd_psr;


wire [7:0] cc = fwd_psr[C] === 1 ? "C" : fwd_psr[C] === 0 ? "-" : "?";
wire [7:0] zc = fwd_psr[Z] === 1 ? "Z" : fwd_psr[Z] === 0 ? "-" : "?";
wire [7:0] ic = fwd_psr[I] === 1 ? "I" : fwd_psr[I] === 0 ? "-" : "?";
wire [7:0] bc = fwd_psr[B] === 1 ? "B" : fwd_psr[B] === 0 ? "-" : "?";
wire [7:0] vc = fwd_psr[V] === 1 ? "V" : fwd_psr[V] === 0 ? "-" : "?";
wire [7:0] nc = fwd_psr[N] === 1 ? "N" : fwd_psr[N] === 0 ? "-" : "?";
initial $monitor("%x %x %x %x %x %x %x %s%s%s%s%s%s %x%xM %x %x %x",
	pc, force_nop, o, fwd_a, fwd_x, fwd_y, fwd_sp, nc, vc, bc, ic, zc, cc,
	wr_u, wr_l, adr_out, data_out, data_in);
endmodule

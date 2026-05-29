module timer #(parameter CLK = 27000000, TIME = 0.005)(clk, wr, active);
input clk, wr;
output active;

localparam N = TIME / (1.0 / $itor(CLK));

reg [19:0] cnt;
assign active = |cnt;

always @(posedge clk)
	if (wr) cnt <= N - 1'b1;
	else if (active) cnt <= cnt - 1'b1;

endmodule

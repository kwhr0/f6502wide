module ram #(parameter FILE="")(clk, ada, douta, adb, dinb, doutb, wreb);
input clk, wreb;
input [13:0] ada, adb;
input [7:0] dinb;
output [7:0] douta, doutb;
reg [7:0] douta, doutb;
reg [7:0] mem[0:'h3fff];
initial $readmemh(FILE, mem);
always @(posedge clk)
	if (wreb) mem[adb] <= dinb;
always @(posedge clk)
	if (wreb & ada == adb) douta <= dinb;
	else douta <= mem[ada];
always @(posedge clk)
	if (wreb) doutb <= dinb;
	else doutb <= mem[adb];
endmodule

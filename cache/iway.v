`timescale 10 ns / 1 ns

module iway #(
	parameter TARRAY_DATA_WIDTH = 24,
	parameter DARRAY_DATA_WIDTH = 256,
	parameter ADDR_WIDTH = 3
)(
	input                            clk,
	input                            rst,
	input  [ADDR_WIDTH - 1:0]        waddr,
	input  [ADDR_WIDTH - 1:0]        raddr,
	input                            wen,
	input                            wvalid,
	input  [TARRAY_DATA_WIDTH - 1:0] wtag,
	input  [DARRAY_DATA_WIDTH - 1:0] wdata,
	output                           rvalid,
	output [TARRAY_DATA_WIDTH - 1:0] rtag,
	output [DARRAY_DATA_WIDTH - 1:0] rdata
);

	/* instantiate valid, tag and data arrays */
	reg [(1 << ADDR_WIDTH) - 1:0] varr;

	tag_array #(
		.TARRAY_DATA_WIDTH(TARRAY_DATA_WIDTH),
		.TARRAY_ADDR_WIDTH(ADDR_WIDTH)
	) tarr (.clk(clk), .waddr(waddr), .raddr(raddr), .wen(wen), .wdata(wtag), .rdata(rtag));

	data_array #(
		.DARRAY_DATA_WIDTH(DARRAY_DATA_WIDTH),
		.DARRAY_ADDR_WIDTH(ADDR_WIDTH)
	) darr (.clk(clk), .waddr(waddr), .raddr(raddr), .wen(wen), .wdata(wdata), .rdata(rdata));

	/* connect valid signal */
	assign rvalid = varr[raddr];
	always @(posedge clk) begin
		if (rst)
			varr <= 0;
		else if (wen)
			varr[waddr] <= wvalid;
	end

endmodule

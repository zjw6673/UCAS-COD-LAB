`timescale 10 ns / 1 ns

module data_array #(
	parameter DARRAY_DATA_WIDTH = 256,
	parameter DARRAY_ADDR_WIDTH = 3
)(
	input                             clk,
	input  [DARRAY_ADDR_WIDTH - 1:0] waddr,
	input  [DARRAY_ADDR_WIDTH - 1:0] raddr,
	input                             wen,
	input  [DARRAY_DATA_WIDTH - 1:0] wdata,
	output [DARRAY_DATA_WIDTH - 1:0] rdata
);

	reg [DARRAY_DATA_WIDTH-1:0] array[ (1 << DARRAY_ADDR_WIDTH) - 1 : 0];
	
	always @(posedge clk)
	begin
		if(wen)
			array[waddr] <= wdata;
	end

assign rdata = array[raddr];

endmodule

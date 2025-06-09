`timescale 10 ns / 1 ns

`define DATA_WIDTH 32

module shifter (
	input  [`DATA_WIDTH - 1:0] A,
	input  [              4:0] B,
	input  [              1:0] Shiftop,
	output [`DATA_WIDTH - 1:0] Result
);
	// TODO: Please add your logic code here
	wire [`DATA_WIDTH-1:0] Shifted1, Shifted2, Shifted4, Shifted8, Shifted16;
	/* compute Shifted1 according to B[0] */
	assign Shifted1 = B[0] ? (
		Shiftop[1] ? (
			Shiftop[0] ? {A[`DATA_WIDTH-1], A[`DATA_WIDTH-1: 1]} // shift right arithmetic
			: {1'b0, A[`DATA_WIDTH-1: 1]} // shift right logical
		) : {A[`DATA_WIDTH-2: 0], 1'b0} // shift left
	) : A;
	/* compute Shifted2 according to B[0] */
	assign Shifted2 = B[1] ? (
		Shiftop[1] ? (
			Shiftop[0] ? {{2{Shifted1[`DATA_WIDTH-1]}}, Shifted1[`DATA_WIDTH-1: 2]} // shift right arithmetic
			: {2'b0, Shifted1[`DATA_WIDTH-1: 2]} // shift right logical
		) : {Shifted1[`DATA_WIDTH-3: 0], 2'b0} // shift left
	) : Shifted1;
	/* compute Shifted4 according to B[0] */
	assign Shifted4 = B[2] ? (
		Shiftop[1] ? (
			Shiftop[0] ? {{4{Shifted2[`DATA_WIDTH-1]}}, Shifted2[`DATA_WIDTH-1: 4]} // shift right arithmetic
			: {4'b0, Shifted2[`DATA_WIDTH-1: 4]} // shift right logical
		) : {Shifted2[`DATA_WIDTH-5: 0], 4'b0} // shift left
	) : Shifted2;
	/* compute Shifted8 according to B[0] */
	assign Shifted8 = B[3] ? (
		Shiftop[1] ? (
			Shiftop[0] ? {{8{Shifted4[`DATA_WIDTH-1]}}, Shifted4[`DATA_WIDTH-1: 8]} // shift right arithmetic
			: {8'b0, Shifted4[`DATA_WIDTH-1: 8]} // shift right logical
		) : {Shifted4[`DATA_WIDTH-9: 0], 8'b0} // shift left
	) : Shifted4;
	/* compute Shifted16 according to B[0] */
	assign Shifted16 = B[4] ? (
		Shiftop[1] ? (
			Shiftop[0] ? {{16{Shifted8[`DATA_WIDTH-1]}}, Shifted8[`DATA_WIDTH-1: 16]} // shift right arithmetic
			: {16'b0, Shifted8[`DATA_WIDTH-1: 16]} // shift right logical
		) : {Shifted8[`DATA_WIDTH-17: 0], 16'b0} // shift left
	) : Shifted8;
	assign Result = Shifted16;
endmodule

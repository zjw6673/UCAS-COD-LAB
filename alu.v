`timescale 10 ns / 1 ns

`define DATA_WIDTH 32

module alu(
	input  [`DATA_WIDTH - 1:0]  A,
	input  [`DATA_WIDTH - 1:0]  B,
	input  [              2:0]  ALUop,
	output                      Overflow,
	output                      CarryOut,
	output                      Zero,
	output [`DATA_WIDTH - 1:0]  Result
);
	// TODO: Please add your logic design here
	wire [`DATA_WIDTH-1:0] ADD, AND, OR;
	wire is_sub, carry;

	/* if is doing sub */
	assign is_sub = ALUop[2];
	/* modify B accordingly */
	wire [`DATA_WIDTH-1:0] modified_B;
	assign modified_B = B ^ {`DATA_WIDTH{is_sub}};
	/* compute add and carryout and overflow */
	assign {carry, ADD} = A + modified_B + {{(`DATA_WIDTH-1){1'b0}}, is_sub};
	assign CarryOut = carry ^ is_sub; // for sub, 0 means carryout, for add 1 means carryout
	assign Overflow = (A[`DATA_WIDTH-1] == modified_B[`DATA_WIDTH-1])
				&& (ADD[`DATA_WIDTH-1] != A[`DATA_WIDTH-1]);
	/* compute and and or */
	assign AND = A & modified_B;
	assign OR = A | modified_B;

	/* assign output */
	assign Result = (AND & {`DATA_WIDTH{(ALUop == 3'b000)}})
		     | (OR & {`DATA_WIDTH{(ALUop == 3'b001)}})
		     | (ADD & {`DATA_WIDTH{(ALUop == 3'b010)}})
		     | (ADD & {`DATA_WIDTH{(ALUop == 3'b110)}})
		     | ({ {(`DATA_WIDTH-1){1'b0}}, ADD[`DATA_WIDTH-1] ^ Overflow}
		     	& {`DATA_WIDTH{(ALUop == 3'b111)}});
	/* compute zero */
	assign Zero = ~{| Result};
endmodule

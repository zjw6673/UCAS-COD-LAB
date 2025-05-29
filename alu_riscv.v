`timescale 10 ns / 1 ns

`define DATA_WIDTH 32

module alu_riscv(
	input  [`DATA_WIDTH - 1:0]  A,
	input  [`DATA_WIDTH - 1:0]  B,
	input  [              2:0]  ALUop,
	output                      Overflow,
	output                      CarryOut,
	output                      Zero,
	output [`DATA_WIDTH - 1:0]  Result
);
	// TODO: Please add your logic design here
	wire [`DATA_WIDTH-1:0] ADD, AND, OR, XOR, NOR;
	wire is_sub, carry;
	wire  altbs; // a less than b signed
	wire  altbu; // a less then b unsigned

	/* if is doing sub */
	assign is_sub = ~ALUop[2] & |ALUop[1:0];
	/* modify B accordingly */
	wire [`DATA_WIDTH-1:0] modified_B;
	assign modified_B = B ^ {`DATA_WIDTH{is_sub}};
	/* compute add and carryout and overflow */
	assign {carry, ADD} = A + modified_B + {{(`DATA_WIDTH-1){1'b0}}, is_sub};
	assign CarryOut = carry ^ is_sub; // for sub, 0 means carryout, for add 1 means carryout
	assign Overflow = (A[`DATA_WIDTH-1] == modified_B[`DATA_WIDTH-1])
				&& (ADD[`DATA_WIDTH-1] != A[`DATA_WIDTH-1]);
	/* compute other signals */
	assign AND = A & modified_B;
	assign OR = A | modified_B;
	assign XOR = A ^ modified_B;
	assign NOR = ~OR;
	assign altbs = ADD[`DATA_WIDTH-1] ^ Overflow;
	assign altbu = A[`DATA_WIDTH-1] ^ B[`DATA_WIDTH-1] ? B[`DATA_WIDTH-1] : altbs;

	/* assign output */
	assign Result = (AND & {`DATA_WIDTH{(ALUop == 3'b111)}})
		     | (OR & {`DATA_WIDTH{(ALUop == 3'b110)}})
		     | (XOR & {`DATA_WIDTH{(ALUop == 3'b100)}})
		     | (NOR & {`DATA_WIDTH{(ALUop == 3'b101)}})
		     | (ADD & {`DATA_WIDTH{(ALUop == 3'b001)}})
		     | (ADD & {`DATA_WIDTH{(ALUop == 3'b000)}})
		     | ({{(`DATA_WIDTH-1){1'b0}}, altbs} & {`DATA_WIDTH{(ALUop == 3'b010)}})
		     | ({{(`DATA_WIDTH-1){1'b0}}, altbu} & {`DATA_WIDTH{(ALUop == 3'b011)}});
	/* compute zero */
	assign Zero = ~{| Result};
endmodule

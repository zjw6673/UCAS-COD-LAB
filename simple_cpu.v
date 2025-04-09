`timescale 10ns / 1ns

module simple_cpu(
	input             clk,
	input             rst,

	output [31:0]     PC,
	input  [31:0]     Instruction,

	output [31:0]     Address,
	output            MemWrite,
	output [31:0]     Write_data,
	output [ 3:0]     Write_strb,

	input  [31:0]     Read_data,
	output            MemRead
);

	// THESE THREE SIGNALS ARE USED IN OUR TESTBENCH
	// PLEASE DO NOT MODIFY SIGNAL NAMES
	// AND PLEASE USE THEM TO CONNECT PORTS
	// OF YOUR INSTANTIATION OF THE REGISTER FILE MODULE
	wire			RF_wen;
	wire [4:0]		RF_waddr;
	wire [31:0]		RF_wdata;
	// TODO: PLEASE ADD YOUR CODE BELOW
	
	/* define signals */
	// reg_file
	wire [4:0] RF_raddr1, RF_raddr2;
	wire [31:0] RF_rdata1, RF_rdata2;
	// shifter
	wire [1:0] shiftOp;
	wire [31:0] shiftTarget, shiftOut;
	wire [4:0] shiftNum;
	// alu
	wire [2:0] aluOp;
	wire [31:0] aluA, aluB, aluOut, aluZero;
	// pc
	// 00 - pc + 8
	// 10 - src1
	// 01 - pc + Sext(imm ## 00)
	// 11 - pc[31:28] ## imm[25:0] ## 00
	localparam pcNextInst = 2'b00, pcJmp = 2'b10, pcOff = 2'b01, pcBranch = 2'b11;
	wire [1:0] pcOp;
	// decode signal
	wire [5:0] opcode, func;
	wire [4:0] rs, rt, rd;
	wire [31:0] src1, src2;
	wire [31:0] immS16, immU16;
	wire [25:0] imm26;
	
	/* instantiate modules */
	// regfile
	reg_file regFile (.clk(clk), .waddr(RF_waddr), .raddr1(RF_raddr1),
		.raddr2(RF_raddr2), .wen(RF_wen), .wdata(RF_wdata),
		.rdata1(RF_rdata1), .rdata2(RF_rdata2));
	// shifter
	shifter shifter (.A(shiftTarget), .B(shiftNum), .Shiftop(shiftOp), .Result(shiftOut));
	// alu
	alu alu (.A(aluA), .B(aluB), .ALUop(aluOp), .Overflow(), .CarryOut(),
		.Zero(aluZero), .Result(aluResult));
	// pc
	reg [31:0] pcReg;
	wire [31:0] pcNext;

	/* decode */
	assign opcode = Instruction[31:26];
	assign rs = Instruction[25:21];
	assign rt = Instruction[20:16];
	assign rd = Instruction[15:11];
	assign func = Instruction[5:0];
	// src
	assign RF_raddr1 = rs;
	assign RF_raddr2 = rt;
	assign src1 = RF_rdata1;
	assign src2 = RF_rdata2;
	// imm
	assign immS16 = {{16{Instruction[15]}}, Instruction[15:0]};
	assign immU16 = {{16{1'b0}}, Instruction[15:0]};
	assign imm26 = Instruction[25:0];
	// pcOp
	wire pcCond = ((~|opcode) & (func[5:3] == 3'b001)) // R_type jump
	            | (opcode[5:1] == 5'b00001) // J_type
	            | ((opcode[5:0] == 6'b000001) & (~|aluZero)) // REGIMM_type
	            | ((opcode[5:2] == 4'b0001) & (|aluZero ^ |opcode[1:0])); // I-BRANCH_type
	wire [1:0] pcCondExt = {2{pcCond}};
	assign pcOp = (~|opcode ? pcJmp	// R_type jump
		: (opcode[5:1] == 5'b00001 ? pcBranch // J_type
		: pcOff // all other types
		)) & pcCondExt;

	// connect pcNext
	wire [31:0] pcOffset = pcOp[0] ? {immS16[31-2:0], 2'b00}: 32'd8;
	wire [31:0] pcMask = pcOp[0] ? {pcReg[31:28], imm26, 2'b00}: src1;
	assign pcNext = pcOp[1] ? pcMask : pcReg + pcOffset;
	// update pc
	always @(posedge clk) begin
		pcReg <= pcNext;
	end

	/* assign Output */
	assign PC = pcReg;
	
endmodule

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
	wire [31:0] aluA, aluB, aluOut;
	wire aluZero;
	// pc
	// 00 - pc + 4
	// 10 - src1
	// 01 - pc + 4 + Sext(imm ## 00)
	// 11 - pc[31:28] ## imm[25:0] ## 00
	wire [1:0] pcOp;
	// decode signal
	wire [5:0] opcode, func;
	wire [4:0] rs, rt, rd, shamt;
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
		.Zero(aluZero), .Result(aluOut));
	// pc
	reg [31:0] pcReg;
	wire [31:0] pcNext;

	/* decode */
	assign opcode = Instruction[31:26];
	assign rs = Instruction[25:21];
	assign rt = Instruction[20:16];
	assign rd = Instruction[15:11];
	assign shamt = Instruction[10:6];
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
	            | ((opcode[5:0] == 6'b000001) & (~aluZero)) // REGIMM_type
	            | ((opcode[5:2] == 4'b0001) & (aluZero ^ |opcode[1:0])); // I-BRANCH_type
	wire [1:0] pcCondExt = {2{pcCond}};
	assign pcOp = (~|opcode ? 2'b10 // R_type jump
		: (opcode[5:1] == 5'b00001 ? 2'b11 // J_type
		: 2'b01 // all other types
		)) & pcCondExt;
	// connect shifter
	assign shiftOp = Instruction[1:0];
	assign shiftTarget = src2;
	assign shiftNum = Instruction[2] ? src1[4:0] : shamt;
	// alu
	assign aluOp = ({func[1], 2'b10} & {3{opcode == 6'b000000 & func[3:2] == 2'b00}}) // add and sub
	             | ({func[1], 1'b0, func[0]} & {3{opcode == 6'b000000 & func[3:2] == 2'b01}}) // and or xor nor
	             | ({~func[0], 2'b11} & {3{opcode == 6'b000000 & func[3:2] == 2'b10}}) // slt and sltu
	             | (3'b111 & {3{opcode == 6'b000001}}) // REGIMM_type
	             | ({2'b11, opcode[1]} & {3{opcode[5:2] == 4'b0001}}) // I-BRANCH_type
	             | (3'b010 & {3{opcode[5:4] == 2'b10}}) // I-MEM_type
	             | (3'b010 & {3{opcode == 6'b001111}}) // lui
	             | ({opcode[1], 2'b10} & {3{opcode[5:3] == 3'b001 & opcode[2:1] == 2'b00}}) // addiu
	             | ({opcode[1], 1'b0, opcode[0]} & {3{opcode[5:3] == 3'b001 & opcode[2] == 1'b1}}) // andi, ori, xori
	             | ({~opcode[0], 2'b11} & {3{opcode[5:3] == 3'b001 & opcode[2:1] == 2'b01}}); // slti, sltiu
	assign aluA = (opcode == 6'b000001 & rt == 5'b00001 ? 32'h11111111
		: (opcode == 6'b000111 ? 32'd0
		: src1
	));
	assign aluB = (src2 & {32{opcode == 6'b000000}}) // R_type
	            | (32'd0 & {32{opcode == 6'b000001 & rt == 5'b00000}}) // bltz
	            | (src1 & {32{opcode == 6'b000001 & rt == 5'b00001}}) // bgez
	            | (src2 & {32{opcode[5:1] == 5'b00010}}) // beq, bne
	            | (32'd1 & {32{opcode == 6'b000110}}) // blez
	            | (src1 & {32{opcode == 6'b000111}}) // blez
	            | (immS16 & {32{opcode == 6'b001001}}) // addiu
	            | ({immS16[15:0], 16'd0} & {32{opcode == 6'b001111}}) // lui
	            | (immU16 & {32{opcode[5:2] == 4'b0011 & ~(opcode[1] & opcode[0])}}) // andi ori xori
	            | (immS16 & {32{opcode[5:1] == 5'b00101}}) // slti sltiu
	            | (immS16 & {32{opcode[5:4] == 2'b10}}); // I-MEM_type
	// MemReadData generate
	wire [7:0] memReadByte = (Read_data[7:0] & {8{aluOut[1:0] == 2'b00}})
	                       | (Read_data[15:8] & {8{aluOut[1:0] == 2'b01}})
	                       | (Read_data[23:16] & {8{aluOut[1:0] == 2'b10}})
	                       | (Read_data[31:24] & {8{aluOut[1:0] == 2'b11}});
	wire [15:0] memReadHalf = (Read_data[15:0] & {16{aluOut[1:0] == 2'b00}})
	                        | (Read_data[31:16] & {16{aluOut[1:0] == 2'b10}});
	wire [31:0] memReadByteS = {{24{memReadByte[7]}}, memReadByte};
	wire [31:0] memReadByteU = {{24{1'b0}}, memReadByte};
	wire [31:0] memReadHalfS = {{16{memReadHalf[15]}}, memReadHalf};
	wire [31:0] memReadHalfU = {{16{1'b0}}, memReadHalf};
	wire [31:0] memReadUpperBytes = ({Read_data[31:24], src2[23:0]} & {32{aluOut[1:0] == 2'b11}})
	                              | ({Read_data[31:16], src2[15:0]} & {32{aluOut[1:0] == 2'b10}})
	                              | ({Read_data[31:8], src2[7:0]} & {32{aluOut[1:0] == 2'b01}})
	                              | (Read_data[31:0] & {32{aluOut[1:0] == 2'b00}});
	wire [31:0] memReadLowerBytes = ({src2[31:8], Read_data[7:0]} & {32{aluOut[1:0] == 2'b00}})
	                              | ({src2[31:16], Read_data[15:0]} & {32{aluOut[1:0] == 2'b01}})
	                              | ({src2[31:24], Read_data[23:0]} & {32{aluOut[1:0] == 2'b10}})
	                              | (Read_data[31:0] & {32{aluOut[1:0] == 2'b11}});
	wire [31:0] memReadData = (memReadByteS & {32{opcode[2:0] == 3'b000}})
	                        | (memReadHalfS & {32{opcode[2:0] == 3'b001}})
	                        | (Read_data & {32{opcode[2:0] == 3'b011}})
	                        | (memReadByteU & {32{opcode[2:0] == 3'b100}})
	                        | (memReadHalfU & {32{opcode[2:0] == 3'b101}})
	                        | (memReadUpperBytes & {32{opcode[2:0] == 3'b010}})
	                        | (memReadLowerBytes & {32{opcode[2:0] == 3'b110}});
	// regfile_write
	assign RF_wen = ((~|opcode) & func[5:3] != 3'b001) // R_type and not Jump or Mov
	              | ((~|opcode) & {func[5:3], func[1]} == 4'b0010 & func[0]) // R_type Jump
	              | ((~|opcode) & {func[5:3], func[1]} == 4'b0011 & (func[0] ^ ~|src2)) // R_type Mov
	              | (opcode == 6'b000011) // jal inst
	              | (opcode[5:3] == 3'b001) // I-Cal_type
	              | (opcode[5:3] == 3'b100); // Memread type
	assign RF_waddr = opcode == 6'b000011 ? 5'd31 // jal
		: (opcode == 6'b000000 ? rd // R_type
		: rt // others
		);
	wire [31:0] nextInst = pcReg + 32'd4;
	assign RF_wdata = (aluOut & {32{(opcode == 6'b000000 & func[5] == 1)}}) // R_type Cal
	                | (shiftOut & {32{(opcode == 6'b000000 & func[5:3] == 3'b000)}}) // R_type shift
	                | (nextInst + 32'd4 & {32{(opcode == 6'b000000 & func[3:0] == 4'b1001)}}) // jalr
	                | (src1 & {32{(opcode == 6'b000000 & {func[5], func[3:1]} == 4'b0101)}}) // R_type Mov
	                | (nextInst + 32'd4 & {32{opcode == 6'b000011}}) // jal
	                | (aluOut & {32{opcode[5:3] == 3'b001}}) // I-Cal_type
	                | (memReadData & {32{opcode[5:3] == 3'b100}}); // MemRead
	// MemWrite
	assign Address = {aluOut[31:2], 2'b00};
	assign MemRead = opcode[5:3] == 3'b100;
	assign MemWrite = opcode[5:3] == 3'b101;
	assign Write_data = src2;
	wire [3:0] memWriteByte = (4'b0001 & {4{aluOut[1:0] == 2'b00}})
	                        | (4'b0010 & {4{aluOut[1:0] == 2'b01}})
	                        | (4'b0100 & {4{aluOut[1:0] == 2'b10}})
	                        | (4'b1000 & {4{aluOut[1:0] == 2'b11}});
	wire [3:0] memWriteHalf = (4'b0011 & {4{aluOut[1:0] == 2'b00}})
	                        | (4'b1100 & {4{aluOut[1:0] == 2'b10}});
	wire [3:0] memWriteUpperBytes = (4'b1000 & {4{aluOut[1:0] == 2'b11}})
	                              | (4'b1100 & {4{aluOut[1:0] == 2'b10}})
	                              | (4'b1110 & {4{aluOut[1:0] == 2'b01}})
	                              | (4'b1111 & {4{aluOut[1:0] == 2'b00}});
	wire [3:0] memWriteLowerBytes = (4'b1111 & {4{aluOut[1:0] == 2'b11}})
	                              | (4'b0111 & {4{aluOut[1:0] == 2'b10}})
	                              | (4'b0011 & {4{aluOut[1:0] == 2'b01}})
	                              | (4'b0001 & {4{aluOut[1:0] == 2'b00}});
	assign Write_strb = (memWriteByte & {4{opcode[2:0] == 3'b000}})
	                  | (memWriteHalf & {4{opcode[2:0] == 3'b001}})
	                  | (4'b1111 & {4{opcode[2:0] == 3'b011}})
	                  | (memWriteUpperBytes & {4{opcode[2:0] == 3'b010}})
	                  | (memWriteLowerBytes & {4{opcode[2:0] == 3'b110}});
	
	/* connect pcNext */
	wire [31:0] pcOffset = pcOp[0] ? {immS16[31-2:0], 2'b00} : 32'd0;
	wire [31:0] pcMask = pcOp[0] ? {pcReg[31:28], imm26, 2'b00}: src1;
	assign pcNext = pcOp[1] ? pcMask : nextInst + pcOffset;
	// update pc
	always @(posedge clk) begin
		if (rst)
			pcReg <= 0;
		else
			pcReg <= pcNext;
	end

	/* assign Output */
	assign PC = pcReg;
	
endmodule

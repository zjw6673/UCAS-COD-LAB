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
	// different major types
	wire is_RType = opcode == 6'b000000;
	wire is_REGIMMType = opcode == 6'b000001;
	wire is_JType = opcode[5:1] == 5'b00001;
	wire is_IBranchType = opcode[5:2] == 4'b0001;
	wire is_ICalType = opcode[5:3] == 3'b001;
	wire is_IMemReadType = opcode[5:3] == 3'b100;
	wire is_IMemWriteType = opcode[5:3] == 3'b101;
	// differet subtypes
	wire is_R_CalType = is_RType & func[5] == 1'b1;
	wire is_R_SType = is_RType & func[5:3] == 3'b000;
	wire is_R_JType = is_RType & func[5:3] == 3'b001 & func[1] == 1'b0;
	wire is_R_MType = is_RType & func[5:3] == 3'b001 & func[1] == 1'b1;
	// special instructions
	// (any special inst that appears only once is not optimized here)
	wire is_jal = opcode == 6'b000011;
	wire is_lui = opcode == 6'b001111;
	wire is_bgez = is_REGIMMType & rt == 5'b00001;
	wire is_bgtz = opcode == 6'b000111;
	wire is_add_sub = is_R_CalType & func[3:2] == 2'b00;
	wire is_and_or_xor_nor = is_R_CalType & func[3:2] == 2'b01;
	wire is_slt_sltu = is_R_CalType & func[3:2] == 2'b10;
	wire is_addiu = is_ICalType & opcode[2:1] == 2'b00;
	wire is_andi_ori_xori = is_ICalType & (opcode[2:1] == 2'b10 | opcode[2:0] == 3'b110);
	wire is_slti_sltiu = is_ICalType & opcode[2:1] == 2'b01;
	wire contain_sb = opcode[2:0] == 3'b000; // contain mains has sb but more than sb
	wire contain_sh = opcode[2:0] == 3'b001;
	wire contain_sw = opcode[2:0] == 3'b011;
	wire contain_swl = opcode[2:0] == 3'b010;
	wire contain_swr = opcode[2:0] == 3'b110;
	// aluout offset(used in mem read and write)
	wire aluOff0 = aluOut[1:0] == 2'b00;
	wire aluOff1 = aluOut[1:0] == 2'b01;
	wire aluOff2 = aluOut[1:0] == 2'b10;
	wire aluOff3 = aluOut[1:0] == 2'b11;
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
	wire pcCond = (is_RType & is_R_JType)
	            | (is_JType)
	            | (is_REGIMMType & (~aluZero))
	            | (is_IBranchType & (aluZero ^ |opcode[1:0]));
	wire [1:0] pcCondExt = {2{pcCond}};
	assign pcOp = (is_RType ? 2'b10
		: (is_JType ? 2'b11
		: 2'b01 // all other types
		)) & pcCondExt;
	// connect shifter
	assign shiftOp = Instruction[1:0];
	assign shiftTarget = src2;
	assign shiftNum = Instruction[2] ? src1[4:0] : shamt;
	// alu
	assign aluOp = ({func[1], 2'b10} & {3{is_add_sub}})
	             | ({func[1], 1'b0, func[0]} & {3{is_and_or_xor_nor}})
	             | ({~func[0], 2'b11} & {3{is_slt_sltu}})
	             | (3'b111 & {3{is_REGIMMType}})
	             | ({2'b11, opcode[1]} & {3{is_IBranchType}})
	             | (3'b010 & {3{is_IMemWriteType | is_IMemReadType}})
	             | (3'b010 & {3{is_lui}})
	             | (3'b010 & {3{is_addiu}})
	             | ({opcode[1], 1'b0, opcode[0]} & {3{is_andi_ori_xori}})
	             | ({~opcode[0], 2'b11} & {3{is_slti_sltiu}});
	assign aluA = (is_bgez ? 32'h11111111
		: (is_bgtz ? 32'd0
		: src1
	));
	assign aluB = (src2 & {32{is_RType}})
	            | (32'd0 & {32{is_REGIMMType & rt[0] == 1'b0}}) // bltz
	            | (src1 & {32{is_bgez}})
	            | (src2 & {32{is_IBranchType & opcode[1] == 1'b0}}) // beq, bne
	            | (32'd1 & {32{opcode == 6'b000110}}) // blez
	            | (src1 & {32{is_bgtz}})
	            | (immS16 & {32{is_addiu}})
	            | ({immS16[15:0], 16'd0} & {32{is_lui}})
	            | (immU16 & {32{is_andi_ori_xori}})
	            | (immS16 & {32{is_slti_sltiu}})
	            | (immS16 & {32{is_IMemReadType | is_IMemWriteType}});
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
	wire [31:0] memReadUpperBytes = (Read_data[31:0] & {32{aluOut[1:0] == 2'b11}})
	                              | ({Read_data[23:0], src2[7:0]} & {32{aluOut[1:0] == 2'b10}})
	                              | ({Read_data[15:0], src2[15:0]} & {32{aluOut[1:0] == 2'b01}})
	                              | ({Read_data[7:0], src2[23:0]} & {32{aluOut[1:0] == 2'b00}});
	wire [31:0] memReadLowerBytes = (Read_data[31:0] & {32{aluOut[1:0] == 2'b00}})
	                              | ({src2[31:24], Read_data[31:8]} & {32{aluOut[1:0] == 2'b01}})
	                              | ({src2[31:16], Read_data[31:16]} & {32{aluOut[1:0] == 2'b10}})
	                              | ({src2[31:8], Read_data[31:24]} & {32{aluOut[1:0] == 2'b11}});
	wire [31:0] memReadData = (memReadByteS & {32{opcode[2:0] == 3'b000}}) // lb
	                        | (memReadHalfS & {32{opcode[2:0] == 3'b001}}) // lh
	                        | (Read_data & {32{opcode[2:0] == 3'b011}}) // lw
	                        | (memReadByteU & {32{opcode[2:0] == 3'b100}}) // lbu
	                        | (memReadHalfU & {32{opcode[2:0] == 3'b101}}) // lhu
	                        | (memReadUpperBytes & {32{opcode[2:0] == 3'b010}}) // lwl
	                        | (memReadLowerBytes & {32{opcode[2:0] == 3'b110}}); // lwr
	// regfile_write
	assign RF_wen = (is_R_CalType | is_R_SType)
	              | (is_R_JType & func[0])
	              | (is_R_MType & (func[0] ^ ~|src2))
	              | is_jal
	              | is_ICalType
	              | is_IMemReadType;
	assign RF_waddr = is_jal ? 5'd31
		: (is_RType ? rd
		: rt // others
		);
	wire [31:0] nextInst = pcReg + 32'd4;
	assign RF_wdata = (aluOut & {32{is_R_CalType}})
	                | (shiftOut & {32{is_R_SType}})
	                | (nextInst + 32'd4 & {32{(is_RType & func[3:0] == 4'b1001)}}) // jalr
	                | (src1 & {32{is_R_MType}})
	                | (nextInst + 32'd4 & {32{is_jal}})
	                | (aluOut & {32{is_ICalType}})
	                | (memReadData & {32{is_IMemReadType}});
	// MemWrite
	assign Address = {aluOut[31:2], 2'b00};
	assign MemRead = is_IMemReadType;
	assign MemWrite = is_IMemWriteType;
	wire [3:0] memWriteByteMask = (4'b0001 & {4{aluOff0}})
	                        | (4'b0010 & {4{aluOff1}})
	                        | (4'b0100 & {4{aluOff2}})
	                        | (4'b1000 & {4{aluOff3}});
	wire [3:0] memWriteHalfMask = (4'b0011 & {4{aluOff0}})
	                        | (4'b1100 & {4{aluOff2}});
	wire [3:0] memWriteUpperBytesMask = (4'b1111 & {4{aluOff3}})
	                              | (4'b0111 & {4{aluOff2}})
	                              | (4'b0011 & {4{aluOff1}})
	                              | (4'b0001 & {4{aluOff0}});
	wire [3:0] memWriteLowerBytesMask = (4'b1000 & {4{aluOff3}})
	                              | (4'b1100 & {4{aluOff2}})
	                              | (4'b1110 & {4{aluOff1}})
	                              | (4'b1111 & {4{aluOff0}});
	assign Write_strb = (memWriteByteMask & {4{contain_sb}})
	                  | (memWriteHalfMask & {4{contain_sh}})
	                  | (4'b1111 & {4{contain_sw}})
	                  | (memWriteUpperBytesMask & {4{contain_swl}})
	                  | (memWriteLowerBytesMask & {4{contain_swr}});
	wire [31:0] memWriteByte = ({4{src2[7:0]}});
	wire [31:0] memWriteHalf = ({2{src2[15:0]}});
	wire [31:0] memWriteUpperBytes = (src2 & {32{aluOff3}})
	                               | ({8'b0, src2[31:8]} & {32{aluOff2}})
	                               | ({16'b0, src2[31:16]} & {32{aluOff1}})
	                               | ({24'b0, src2[31:24]} & {32{aluOff0}});
	wire [31:0] memWriteLowerBytes = ({src2[7:0], 24'b0} & {32{aluOff3}})
	                               | ({src2[15:0], 16'b0} & {32{aluOff2}})
	                               | ({src2[23:0], 8'b0} & {32{aluOff1}})
	                               | (src2[31:0] & {32{aluOff0}});
	assign Write_data = (memWriteByte & {32{contain_sb}})
	                  | (memWriteHalf & {32{contain_sh}})
	                  | (src2 & {32{contain_sw}})
	                  | (memWriteUpperBytes & {32{contain_swl}}) 
	                  | (memWriteLowerBytes & {32{contain_swr}});
	
	/* connect pcNext */
	wire [31:0] pcOffset = pcOp[0] ? {immS16[31-2:0], 2'b00} : 32'd0;
	wire [31:0] pcMask = pcOp[0] ? {pcReg[31:28], imm26, 2'b00}: src1;
	assign pcNext = pcOp[1] ? pcMask : (nextInst + pcOffset);
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

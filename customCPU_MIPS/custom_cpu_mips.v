`timescale 10ns / 1ns

module custom_cpu(
	input         clk,
	input         rst,

	//Instruction request channel
	output [31:0] PC,
	output        Inst_Req_Valid,
	input         Inst_Req_Ready,

	//Instruction response channel
	input  [31:0] Instruction,
	input         Inst_Valid,
	output        Inst_Ready,

	//Memory request channel
	output [31:0] Address,
	output        MemWrite,
	output [31:0] Write_data,
	output [ 3:0] Write_strb,
	output        MemRead,
	input         Mem_Req_Ready,

	//Memory data response channel
	input  [31:0] Read_data,
	input         Read_data_Valid,
	output        Read_data_Ready,

	input         intr,

	output [31:0] cpu_perf_cnt_0,
	output [31:0] cpu_perf_cnt_1,
	output [31:0] cpu_perf_cnt_2,
	output [31:0] cpu_perf_cnt_3,
	output [31:0] cpu_perf_cnt_4,
	output [31:0] cpu_perf_cnt_5,
	output [31:0] cpu_perf_cnt_6,
	output [31:0] cpu_perf_cnt_7,
	output [31:0] cpu_perf_cnt_8,
	output [31:0] cpu_perf_cnt_9,
	output [31:0] cpu_perf_cnt_10,
	output [31:0] cpu_perf_cnt_11,
	output [31:0] cpu_perf_cnt_12,
	output [31:0] cpu_perf_cnt_13,
	output [31:0] cpu_perf_cnt_14,
	output [31:0] cpu_perf_cnt_15,

	output [69:0] inst_retire
);

/* The following signal is leveraged for behavioral simulation, 
* which is delivered to testbench.
*
* STUDENTS MUST CONTROL LOGICAL BEHAVIORS of THIS SIGNAL.
*
* inst_retired (70-bit): detailed information of the retired instruction,
* mainly including (in order) 
* { 
*   reg_file write-back enable  (69:69,  1-bit),
*   reg_file write-back address (68:64,  5-bit), 
*   reg_file write-back data    (63:32, 32-bit),  
*   retired PC                  (31: 0, 32-bit)
* }
*
*/
  // wire [69:0] inst_retire;

// TODO: Please add your custom CPU code here

	/* define states */
	localparam INIT = 9'b000000001,
	           IF   = 9'b000000010,
	           IW   = 9'b000000100,
	           ID   = 9'b000001000,
	           EX   = 9'b000010000,
	           ST   = 9'b000100000,
	           WB   = 9'b001000000,
	           LD   = 9'b010000000,
	           RDW  = 9'b100000000;
	reg [8:0] current_state;
	reg [8:0] next_state;

	/* create inner signals */
	// reg_file
	wire RF_wen;
	wire [4:0] RF_raddr1, RF_raddr2, RF_waddr;
	wire [31:0] RF_rdata1, RF_rdata2, RF_wdata;
	// shifter
	wire [1:0] shiftOp;
	wire [4:0] shiftNum;
	wire [31:0] shiftTarget, shiftOut;
	// alu
	wire [2:0] aluOp;
	wire [31:0] aluA, aluB, aluOut;
	wire aluZero;
	// pc
	wire [1:0] pcOp;
	reg [31:0] pcReg;
	wire [31:0] pcNext;
	// instruction
	reg [31:0] instReg;
	// mem
	reg [31:0] readDataReg;

	/* create decode signals */
	wire [5:0] opcode  = instReg[31:26];
	wire [4:0] rs      = instReg[25:21];
	wire [4:0] rt      = instReg[20:16];
	wire [4:0] rd      = instReg[15:11];
	wire [4:0] shamt   = instReg[10:6];
	wire [5:0] func    = instReg[5:0];
	// different major types
	wire is_RType          = opcode == 6'b000000;
	wire is_REGIMMType     = opcode == 6'b000001;
	wire is_JType          = opcode[5:1] == 5'b00001;
	wire is_IBranchType    = opcode[5:2] == 4'b0001;
	wire is_ICalType       = opcode[5:3] == 3'b001;
	wire is_IMemReadType   = opcode[5:3] == 3'b100;
	wire is_IMemWriteType  = opcode[5:3] == 3'b101;
	// differet subtypes
	wire is_R_CalType      = is_RType & func[5] == 1'b1;
	wire is_R_SType        = is_RType & func[5:3] == 3'b000;
	wire is_R_JType        = is_RType & func[5:3] == 3'b001 & func[1] == 1'b0;
	wire is_R_MType        = is_RType & func[5:3] == 3'b001 & func[1] == 1'b1;
	// special instructions
	wire is_nop            = instReg == 32'b0;
	wire is_jr             = (is_R_JType & ~func[0]);
	wire is_jalr           = (is_R_JType & func[0]);
	wire is_j              = (is_JType & ~opcode[0]);
	wire is_jal            = (is_JType & opcode[0]);
	wire is_lui            = opcode == 6'b001111;
	wire is_beq_bne        = is_IBranchType & opcode[1] == 1'b0;
	wire is_blez           = is_IBranchType & opcode[1:0] == 2'b10;
	wire is_bgtz           = is_IBranchType & opcode[1:0] == 2'b11;
	wire is_bltz           = is_REGIMMType & rt[0] == 1'b0;
	wire is_bgez           = is_REGIMMType & rt[0] == 1'b1;
	wire is_add_sub        = is_R_CalType & func[3:2] == 2'b00;
	wire is_and_or_xor_nor = is_R_CalType & func[3:2] == 2'b01;
	wire is_slt_sltu       = is_R_CalType & func[3:2] == 2'b10;
	wire is_addiu          = is_ICalType & opcode[2:1] == 2'b00;
	wire is_andi_ori_xori  = is_ICalType & (opcode[2:1] == 2'b10 | opcode[2:0] == 3'b110);
	wire is_slti_sltiu     = is_ICalType & opcode[2:1] == 2'b01;
	wire contain_b         = opcode[2:0] == 3'b000; // this mains has sb or lb
	wire contain_h         = opcode[2:0] == 3'b001;
	wire contain_w         = opcode[2:0] == 3'b011;
	wire contain_bu        = opcode[2:0] == 3'b100;
	wire contain_hu        = opcode[2:0] == 3'b101;
	wire contain_wl        = opcode[2:0] == 3'b010;
	wire contain_wr        = opcode[2:0] == 3'b110;
	// aluout offset(used in mem read and write)
	wire aluOff0           = aluOut[1:0] == 2'b00;
	wire aluOff1           = aluOut[1:0] == 2'b01;
	wire aluOff2           = aluOut[1:0] == 2'b10;
	wire aluOff3           = aluOut[1:0] == 2'b11;
	// src
	assign RF_raddr1   = rs;
	assign RF_raddr2   = rt;
	wire [31:0] src1   = RF_rdata1;
	wire [31:0] src2   = RF_rdata2;
	// imm
	wire [31:0] immS16 = {{16{instReg[15]}}, instReg[15:0]};
	wire [31:0] immU16 = {{16{1'b0}}, instReg[15:0]};
	wire [25:0] imm26  = instReg[25:0];
	// pcOp
	wire pcCond = is_R_JType
	            | is_JType
	            | (is_REGIMMType & (~aluZero))
	            | (is_IBranchType & (aluZero ^ |opcode[1:0]));
	wire [1:0] pcCondExt = {2{pcCond}};
	assign pcOp = (is_RType ? 2'b10
	            : (is_JType ? 2'b11
	            :             2'b01 )) & pcCondExt;

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

	/* FSM: section 1 (update current_state) */
	always @(posedge clk) begin
		if (rst == 1'b1)
			current_state <= INIT;
		else
			current_state <= next_state;
	end

	/* FSM: section 2 (update next_state) */
	always @(*) begin
		case(current_state)
			INIT: begin
				next_state = IF;
			end
			IF: begin
				if (Inst_Req_Ready == 1'b1)
					next_state = IW;
				else
					next_state = IF;
			end
			IW: begin
				if (Inst_Valid == 1'b1)
					next_state = ID;
				else
					next_state = IW;
			end
			ID: begin
				if (is_nop)
					next_state = IF;
				else
					next_state = EX;
			end
			EX: begin
				if (is_REGIMMType | is_IBranchType | is_j )
					next_state = IF;
				else if (is_IMemWriteType)
					next_state = ST;
				else if (is_IMemReadType)
					next_state = LD;
				else
					next_state = WB;
			end
			ST: begin
				if (Mem_Req_Ready)
					next_state = IF;
				else
					next_state = ST;
			end
			WB: begin
				next_state = IF;
			end
			LD: begin
				if (Mem_Req_Ready)
					next_state = RDW;
				else
					next_state = LD;
			end
			RDW: begin
				if (Read_data_Valid)
					next_state = WB;
				else
					next_state = RDW;
			end
			default:
				next_state = INIT;
		endcase
	end

	/* FSM: section 3 (all other signals) */
	// connect hand shakes
	assign Inst_Req_Valid  = (current_state == IF)                         ? 1'b1 : 1'b0;
	assign Inst_Ready      = (current_state == IW | current_state == INIT) ? 1'b1 : 1'b0;
	assign MemRead         = (current_state == LD)                         ? 1'b1 : 1'b0;
	assign Read_data_Ready = (current_state == RDW| current_state == INIT) ? 1'b1 : 1'b0;
	assign MemWrite        = (current_state == ST)                         ? 1'b1 : 1'b0;
	// update inst (store inst right after IW state)
	always @(posedge clk) begin
		if (current_state == IW)
			instReg <= Instruction;
		else
			instReg <= instReg;
	end
	// connect pc (pc updates on arrival of IF state)
	wire [31:0] staticNextPc = pcReg + 32'd4;
	wire [31:0] pcOffset = pcOp[0] ? {immS16[31-2:0], 2'b00}      : 32'd0;
	wire [31:0] pcMask   = pcOp[0] ? {pcReg[31:28], imm26, 2'b00} : src1;
	assign pcNext = pcOp[1] ? pcMask : (staticNextPc + pcOffset);
	always @(posedge clk) begin
		if (rst)
			pcReg <= 32'd0;
		else if (current_state == WB
		 | (current_state == ST & Mem_Req_Ready)
		 | (current_state == EX & (is_REGIMMType|is_IBranchType|is_j))
		 | (current_state == ID & is_nop))
			pcReg <= pcNext;
		else
			pcReg <= pcReg;
	end
	assign PC = pcReg;
	// connect shifter
	assign shiftOp     = instReg[1:0];
	assign shiftTarget = src2;
	assign shiftNum    = instReg[2] ? src1[4:0] : shamt;
	// connect alu
	assign aluOp = ({func[1], 2'b10}             & {3{is_add_sub}})
	             | ({func[1], 1'b0, func[0]}     & {3{is_and_or_xor_nor}})
	             | ({~func[0], 2'b11}            & {3{is_slt_sltu}})
	             | (3'b111                       & {3{is_REGIMMType}})
	             | ({2'b11, opcode[1]}           & {3{is_IBranchType}})
	             | (3'b010                       & {3{is_IMemWriteType | is_IMemReadType | is_lui | is_addiu | is_jal | is_jalr}})
	             | ({opcode[1], 1'b0, opcode[0]} & {3{is_andi_ori_xori}})
	             | ({~opcode[0], 2'b11}          & {3{is_slti_sltiu}});
	assign aluA = (is_bgez            ? 32'hffffffff
	            : (is_bgtz            ? 32'd0
		    : ((is_jal | is_jalr) ? staticNextPc
	            :                       src1 )));
	assign aluB = (src2                  & {32{is_RType | is_beq_bne}})
	            | (32'd4                 & {32{is_jal | is_jalr}})
	            | (32'd0                 & {32{is_bltz}})
	            | (src1                  & {32{is_bgez | is_bgtz}})
	            | (32'd1                 & {32{is_blez}})
	            | ({immS16[15:0], 16'd0} & {32{is_lui}})
	            | (immU16                & {32{is_andi_ori_xori}})
	            | (immS16                & {32{is_addiu | is_slti_sltiu | is_IMemReadType | is_IMemWriteType}});
	// generate MemReadData
	always @(posedge clk) begin // update readDataReg right after RDW state
		if (current_state == RDW)
			readDataReg <= Read_data;
		else
			readDataReg <= readDataReg;
	end
	wire [7:0] memReadByte        = (readDataReg[7:0]                  & {8{aluOff0}})
	                              | (readDataReg[15:8]                 & {8{aluOff1}})
	                              | (readDataReg[23:16]                & {8{aluOff2}})
	                              | (readDataReg[31:24]                & {8{aluOff3}});
	wire [15:0] memReadHalf       = (readDataReg[15:0]                 & {16{aluOff0}})
	                              | (readDataReg[31:16]                & {16{aluOff2}});
	wire [31:0] memReadByteS      = {{24{memReadByte[7]}} , memReadByte}; // sign extend
	wire [31:0] memReadByteU      = {{24{1'b0}}           , memReadByte}; // unsign extend
	wire [31:0] memReadHalfS      = {{16{memReadHalf[15]}}, memReadHalf};
	wire [31:0] memReadHalfU      = {{16{1'b0}}           , memReadHalf};
	wire [31:0] memReadUpperBytes = (readDataReg[31:0]                 & {32{aluOff3}})
	                              | ({readDataReg[23:0], src2[7:0]}    & {32{aluOff2}})
	                              | ({readDataReg[15:0], src2[15:0]}   & {32{aluOff1}})
	                              | ({readDataReg[7:0], src2[23:0]}    & {32{aluOff0}});
	wire [31:0] memReadLowerBytes = (readDataReg[31:0]                 & {32{aluOff0}})
	                              | ({src2[31:24], readDataReg[31:8]}  & {32{aluOff1}})
	                              | ({src2[31:16], readDataReg[31:16]} & {32{aluOff2}})
	                              | ({src2[31:8], readDataReg[31:24]}  & {32{aluOff3}});
	wire [31:0] memReadData       = (memReadByteS                      & {32{contain_b}})
	                              | (memReadHalfS                      & {32{contain_h}})
	                              | (readDataReg                       & {32{contain_w}})
	                              | (memReadByteU                      & {32{contain_bu}})
	                              | (memReadHalfU                      & {32{contain_hu}})
	                              | (memReadUpperBytes                 & {32{contain_wl}})
	                              | (memReadLowerBytes                 & {32{contain_wr}});
	// connect memory
	assign Address = {aluOut[31:2], 2'b00};
	wire [31:0] memWriteByte       = ({4{src2[7:0]}});
	wire [31:0] memWriteHalf       = ({2{src2[15:0]}});
	wire [31:0] memWriteUpperBytes = (src2                 & {32{aluOff3}})
	                               | ({8'b0, src2[31:8]}   & {32{aluOff2}})
	                               | ({16'b0, src2[31:16]} & {32{aluOff1}})
	                               | ({24'b0, src2[31:24]} & {32{aluOff0}});
	wire [31:0] memWriteLowerBytes = ({src2[7:0], 24'b0}   & {32{aluOff3}})
	                               | ({src2[15:0], 16'b0}  & {32{aluOff2}})
	                               | ({src2[23:0], 8'b0}   & {32{aluOff1}})
	                               | (src2[31:0]           & {32{aluOff0}});
	assign Write_data = (memWriteByte       & {32{contain_b}})
	                  | (memWriteHalf       & {32{contain_h}})
	                  | (src2               & {32{contain_w}})
	                  | (memWriteUpperBytes & {32{contain_wl}}) 
	                  | (memWriteLowerBytes & {32{contain_wr}});
	wire [3:0] memWriteByteMask       = (4'b0001 & {4{aluOff0}})
	                                  | (4'b0010 & {4{aluOff1}})
	                                  | (4'b0100 & {4{aluOff2}})
	                                  | (4'b1000 & {4{aluOff3}});
	wire [3:0] memWriteHalfMask       = (4'b0011 & {4{aluOff0}})
	                                  | (4'b1100 & {4{aluOff2}});
	wire [3:0] memWriteUpperBytesMask = (4'b1111 & {4{aluOff3}})
	                                  | (4'b0111 & {4{aluOff2}})
	                                  | (4'b0011 & {4{aluOff1}})
	                                  | (4'b0001 & {4{aluOff0}});
	wire [3:0] memWriteLowerBytesMask = (4'b1000 & {4{aluOff3}})
	                                  | (4'b1100 & {4{aluOff2}})
	                                  | (4'b1110 & {4{aluOff1}})
	                                  | (4'b1111 & {4{aluOff0}});
	assign Write_strb = (memWriteByteMask       & {4{contain_b}})
	                  | (memWriteHalfMask       & {4{contain_h}})
	                  | (4'b1111                & {4{contain_w}})
	                  | (memWriteUpperBytesMask & {4{contain_wl}})
	                  | (memWriteLowerBytesMask & {4{contain_wr}});
	// connect regfile
	assign RF_waddr = (is_jal   ? 5'd31
	                : (is_RType ? rd
		              :             rt ));
	assign RF_wdata = (aluOut               & {32{is_R_CalType | is_ICalType | is_jalr | is_jal}})
	                | (shiftOut             & {32{is_R_SType}})
	                | (src1                 & {32{is_R_MType}})
	                | (memReadData          & {32{is_IMemReadType}});
	assign RF_wen = (current_state != WB | is_jr) ? 1'b0
	              : (is_R_MType                   ? |src2 ^ ~func[0]
	              :                                 1'b1);

	/* performance counter */
	reg [31:0] cycle_cnt;
	always @(posedge clk) begin
		if (rst == 1'b1)
			cycle_cnt <= 32'd0;
		else
			cycle_cnt <= cycle_cnt + 32'd1;
	end
	assign cpu_perf_cnt_0 = cycle_cnt;

	reg [31:0] inst_cnt;
	always @(posedge clk) begin
		if (rst == 1'b1)
			inst_cnt <= 32'd0;
		else if (current_state == ID) // each inst goes through ID state for exactly one cycle
			inst_cnt <= inst_cnt + 32'd1;
		else
			inst_cnt <= inst_cnt;
	end
	assign cpu_perf_cnt_1 = inst_cnt;

	reg [31:0] mem_read_inst_cnt;
	always @(posedge clk) begin
		if (rst == 1'b1)
			mem_read_inst_cnt <= 32'd0;
		else if (current_state == ID && is_IMemReadType)
			mem_read_inst_cnt <= mem_read_inst_cnt + 32'd1;
		else
			mem_read_inst_cnt <= mem_read_inst_cnt;
	end
	assign cpu_perf_cnt_2 = mem_read_inst_cnt;

	reg [31:0] mem_write_inst_cnt;
	always @(posedge clk) begin
		if (rst == 1'b1)
			mem_write_inst_cnt <= 32'd0;
		else if (current_state == ID && is_IMemWriteType)
			mem_write_inst_cnt <= mem_write_inst_cnt + 32'd1;
		else
			mem_write_inst_cnt <= mem_write_inst_cnt;
	end
	assign cpu_perf_cnt_3 = mem_write_inst_cnt;

	reg [31:0] mem_read_req_cycle_cnt;
	always @(posedge clk) begin
		if (rst == 1'b1)
			mem_read_req_cycle_cnt <= 32'd0;
		else if (current_state == LD)
			mem_read_req_cycle_cnt <= mem_read_req_cycle_cnt + 32'd1;
		else
			mem_read_req_cycle_cnt <= mem_read_req_cycle_cnt;
	end
	assign cpu_perf_cnt_4 = mem_read_req_cycle_cnt;

	reg [31:0] mem_read_wait_cycle_cnt;
	always @(posedge clk) begin
		if (rst == 1'b1)
			mem_read_wait_cycle_cnt <= 32'd0;
		else if (current_state == RDW)
			mem_read_wait_cycle_cnt <= mem_read_wait_cycle_cnt + 32'd1;
		else
			mem_read_wait_cycle_cnt <= mem_read_wait_cycle_cnt;
	end
	assign cpu_perf_cnt_5 = mem_read_wait_cycle_cnt;

	reg [31:0] mem_write_req_cycle_cnt;
	always @(posedge clk) begin
		if (rst == 1'b1)
			mem_write_req_cycle_cnt <= 32'd0;
		else if (current_state == ST)
			mem_write_req_cycle_cnt <= mem_write_req_cycle_cnt + 32'd1;
		else
			mem_write_req_cycle_cnt <= mem_write_req_cycle_cnt;
	end
	assign cpu_perf_cnt_6 = mem_write_req_cycle_cnt;

	reg [31:0] bj_inst_cnt;
	always @(posedge clk) begin
		if (rst == 1'b1)
			bj_inst_cnt <= 32'd0;
		else if (current_state == ID && (is_REGIMMType | is_IBranchType | is_JType | is_R_JType))
			bj_inst_cnt <= bj_inst_cnt + 32'd1;
		else
			bj_inst_cnt <= bj_inst_cnt;
	end
	assign cpu_perf_cnt_7 = bj_inst_cnt;
endmodule

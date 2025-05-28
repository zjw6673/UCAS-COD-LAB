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
  assign inst_retire[69] = RF_wen;
  assign inst_retire[68:64] = RF_waddr;
  assign inst_retire[63:32] = RF_wdata;
  assign inst_retire[31:0] = pcReg;

// TODO: Please add your custom CPU code here

	/* define states */
	localparam INIT = 9'b000000001,
	           IF   = 9'b000000010,
	           IW   = 9'b000000100,
	           ID   = 9'b000001000,
	           EX   = 9'b000010000,
	           ST   = 9'b000100000,
	           LD   = 9'b001000000,
	           RDW  = 9'b010000000,
	           WB   = 9'b100000000;
	reg [8:0] current_state, next_state;
	
	/* create inner wires */
	// regfile
	wire        RF_wen;
	wire [ 4:0] RF_raddr1, RF_raddr2, RF_waddr;
	wire [31:0] RF_rdata1, RF_rdata2, RF_wdata;
	// shifter
	wire [ 1:0] shiftOp;
	wire [ 4:0] shamt;
	wire [31:0] shiftTarget, shiftOut;
	// alu
	wire [ 2:0] aluOp;
	wire [31:0] aluA, aluB, aluOut;
	wire        aluZero;
	// pc
	reg  [31:0] pcReg, nextPc;
	wire [31:0] snpc; // static next pc, namely pc + 4
	wire [31:0] bnpc; // branch next pc, namely pc of possible branch
	wire [31:0] dnpc; // dynammic next pc, the real pc for next inst
	// mem
	reg  [31:0] readDataReg;
	// inst
	reg  [31:0] instReg;

	/* instantiate modules */
	// regfile
	reg_file regFile (.clk(clk), .waddr(RF_waddr), .raddr1(RF_raddr1),
	                  .raddr2(RF_raddr2), .wen(RF_wen), .wdata(RF_wdata),
	                  .rdata1(RF_rdata1), .rdata2(RF_rdata2));
	// shifter
	shifter shifter (.A(shiftTarget), .B(shamt), .Shiftop(shiftOp), .Result(shiftOut));
	// alu
	alu alu (.A(aluA), .B(aluB), .ALUop(aluOp), .Overflow(), .CarryOut(),
	         .Zero(aluZero), .Result(aluOut));
	
	/* create decode signals */
	// first layer
	wire [6:0] opcode = instReg[ 6: 0];
	wire [2:0] func3  = instReg[14:12];
	wire [6:0] func7  = instReg[31:25];
	wire [4:0] rs1    = instReg[19:15];
	wire [4:0] rs2    = instReg[24:20];
	wire [4:0] rd     = instReg[11: 7];
	wire [7:0] func; // convert func3 to onehot
	assign func[0] = (func3 == 3'b000);
	assign func[1] = (func3 == 3'b001);
	assign func[2] = (func3 == 3'b010);
	assign func[3] = (func3 == 3'b011);
	assign func[4] = (func3 == 3'b100);
	assign func[5] = (func3 == 3'b101);
	assign func[6] = (func3 == 3'b110);
	assign func[7] = (func3 == 3'b111);
	// second layer
	wire is_RType     = (opcode[6:2] == 5'b01100);
	wire is_I_CalType = (opcode[6:2] == 5'b00100);
	wire is_I_LDType  = (opcode[6:2] == 5'b00000);
	wire is_I_JType   = (opcode[6:2] == 5'b11001);
	wire is_SType     = (opcode[6:2] == 5'b01000);
	wire is_BType     = (opcode[6:2] == 5'b11000);
	wire is_LUI       = (opcode[6:2] == 5'b01101);
	wire is_AUIPC     = (opcode[6:2] == 5'b00101);
	wire is_JType     = (opcode[6:2] == 5'b11011);
	// third layer
	wire is_shiftType = ((is_RType | is_I_CalType) & (func[1] | func[5]));
	wire is_IType     = (is_I_CalType | is_I_LDType | is_I_JType);
	wire is_UType     = (is_LUI | is_AUIPC);
	// operands: sext(imm) generator
	wire [31:0] sext_imm;
	assign sext_imm = ({ {20{instReg[31]}}, instReg[31:20] }                                    & {32{is_IType}})
	                | ({ {20{instReg[31]}}, instReg[31:25], instReg[11:7] }                     & {32{is_SType}})
	                | ({ {20{instReg[31]}}, instReg[7], instReg[30:25], instReg[11:8], 1'b0 }   & {32{is_BType}})
	                | ({ instReg[31:12], 12'd0 }                                                & {32{is_UType}})
	                | ({ {12{instReg[31]}}, instReg[19:12], instReg[20], instReg[30:21], 1'b0 } & {32{is_JType}});
	// operands: src1 and src2
	wire [31:0] src1, src2;
	// aluOut offset
	wire aluOff0 = (aluOut[1:0] == 2'b00);
	wire aluOff1 = (aluOut[1:0] == 2'b01);
	wire aluOff2 = (aluOut[1:0] == 2'b10);
	wire aluOff3 = (aluOut[1:0] == 2'b11);

	/* FSM: section 1 */
	always @(posedge clk) begin
		if (rst == 1'b1)
			current_state <= INIT;
		else
			current_state <= next_state;
	end

	/* FSM: section 2 */
	always @(*) begin
		case(current_state)
			INIT:
				next_state = IF;
			IF:
				if (Inst_Req_Ready)
					next_state = IW;
				else
					next_state = IF;
			IW:
				if (Inst_Valid)
					next_state = ID;
				else
					next_state = IW;
			ID:
				next_state = EX;
			EX:
				if (is_BType)
					next_state = IF;
				else if (is_SType)
					next_state = ST;
				else if (is_I_LDType)
					next_state = LD;
				else
					next_state = WB;
			ST:
				if (Mem_Req_Ready)
					next_state = IF;
				else
					next_state = ST;
			LD:
				if (Mem_Req_Ready)
					next_state = RDW;
				else
					next_state = LD;
			RDW: if (Read_data_Valid) next_state = WB; else
					next_state = RDW;
			WB:
				next_state = IF;
			default:
				next_state = INIT;
		endcase
	end

	/* FSM section 3 */
	// connect handshake
	assign Inst_Req_Valid  = (current_state == IF)                          ? 1'b1 : 1'b0;
	assign Inst_Ready      = (current_state == IW | current_state == INIT)  ? 1'b1 : 1'b0;
	assign MemRead         = (current_state == LD)                          ? 1'b1 : 1'b0;
	assign Read_data_Ready = (current_state == RDW | current_state == INIT) ? 1'b1 : 1'b0;
	assign MemWrite        = (current_state == ST)                          ? 1'b1 : 1'b0;
	// registers
	always @(posedge clk) begin // update instReg at end of IW
		if (current_state == IW)
			instReg <= Instruction;
		else
			instReg <= instReg;
	end
	always @(posedge clk) begin // update readDataReg at end of RDW
		if (current_state == RDW)
			readDataReg <= Read_data;
		else
			readDataReg <= readDataReg;
	end
	always @(posedge clk) begin // update pcReg at end of IW, indicate the pc for current inst
		if (current_state == IW)
			pcReg <= nextPc;
		else
			pcReg <= pcReg;
	end
	always @(posedge clk) begin // update nextPc at end of EX and INIT
		if (current_state == INIT)
			nextPc <= 32'd0;
		else if (current_state == EX)
			nextPc <= dnpc;
		else
			nextPc <= nextPc;
	end
	// connect pc signals
	assign PC = nextPc; // connext PC to nextPc
	assign snpc = pcReg + 32'd4;
	wire [31:0] bnpc_src = (is_I_JType) ? src1 : pcReg;
	assign bnpc = bnpc_src + sext_imm;
	assign dnpc =  (is_JType)                                           ? bnpc
	            : ((is_I_JType)                                         ? {bnpc[31:1], 1'b0}
	            : ((is_BType & |{func[0], func[5], func[7]} & aluZero)  ? bnpc
	            : ((is_BType & |{func[1], func[4], func[6]} & ~aluZero) ? bnpc 
	            :                                                         snpc )));
	// connect shifter
	assign shiftOp     = (2'b00   & {2{func[1]            }})  // sll slli
	                   | (2'b11   & {2{func[5] &  func7[5]}})  // sra srai
	                   | (2'b10   & {2{func[5] & ~func7[5]}}); // srl srli
	assign shiftTarget = src1;
	assign shamt       = (is_I_CalType) ? sext_imm[4:0] : src2[4:0];
	// connect alu
	assign aluA  = (is_AUIPC) ? pcReg : src1;
	assign aluB  = (is_RType | is_BType) ?  src2 : sext_imm;
	assign aluOp = (3'b010 & {3{is_I_LDType | is_SType | is_AUIPC | (is_RType & func[0] & ~func7[5]) | (is_I_CalType & func[0])}})
	             | (3'b110 & {3{(is_RType & func[0] & func7[5]) | (is_BType & func[0]) | (is_BType & func[1])}})
	             | (3'b000 & {3{(is_RType | is_I_CalType) & func[7]}})
	             | (3'b001 & {3{(is_RType | is_I_CalType) & func[6]}})
	             | (3'b100 & {3{(is_RType | is_I_CalType) & func[4]}})
	             | (3'b111 & {3{((is_RType | is_I_CalType) & func[2]) | (is_BType & (func[4] | func[5]))}})
	             | (3'b011 & {3{((is_RType | is_I_CalType) & func[3]) | (is_BType & (func[6] | func[7]))}});
	// connect memory write
	assign Address = {aluOut[31:2], 2'b00};
	assign Write_data = ( {4{src2[7:0]}}  & {32{func[0]}} )
	                  | ( {2{src2[15:0]}} & {32{func[1]}} )
	                  | ( src2            & {32{func[2]}} );
	assign Write_strb[0] = (func[0] & aluOff0) | (func[1] & aluOff0) | func[2];
	assign Write_strb[1] = (func[0] & aluOff1) | (func[1] & aluOff0) | func[2];
	assign Write_strb[2] = (func[0] & aluOff2) | (func[1] & aluOff2) | func[2];
	assign Write_strb[3] = (func[0] & aluOff3) | (func[1] & aluOff2) | func[2];
	// process memory read
	wire [31:0] readData_processed;
	assign readData_processed = (readDataReg                                 & {32{func[2]}})
	                          | ({16'd0,                 readDataReg[15: 0]} & {32{func[5] & aluOff0}})
	                          | ({16'd0,                 readDataReg[31:16]} & {32{func[5] & aluOff2}})
	                          | ({{16{readDataReg[15]}}, readDataReg[15: 0]} & {32{func[1] & aluOff0}})
	                          | ({{16{readDataReg[31]}}, readDataReg[31:16]} & {32{func[1] & aluOff2}})
	                          | ({24'd0,                 readDataReg[ 7: 0]} & {32{func[4] & aluOff0}})
	                          | ({24'd0,                 readDataReg[15: 8]} & {32{func[4] & aluOff1}})
	                          | ({24'd0,                 readDataReg[23:16]} & {32{func[4] & aluOff2}})
	                          | ({24'd0,                 readDataReg[31:24]} & {32{func[4] & aluOff3}})
	                          | ({{24{readDataReg[ 7]}}, readDataReg[ 7: 0]} & {32{func[0] & aluOff0}})
	                          | ({{24{readDataReg[15]}}, readDataReg[15: 8]} & {32{func[0] & aluOff1}})
	                          | ({{24{readDataReg[23]}}, readDataReg[23:16]} & {32{func[0] & aluOff2}})
	                          | ({{24{readDataReg[31]}}, readDataReg[31:24]} & {32{func[0] & aluOff3}});
	// connect regfile
	assign RF_raddr1 = rs1;
	assign RF_raddr2 = rs2;
	assign src1 = RF_rdata1;
	assign src2 = RF_rdata2;
	assign RF_waddr = rd;
	assign RF_wen = (current_state == WB);
	assign RF_wdata =  (is_I_LDType)           ? readData_processed
	                : ((is_I_JType | is_JType) ? snpc
	                : ((is_LUI)                ? sext_imm
	                : ((is_shiftType)          ? shiftOut
	                :                            aluOut )));

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
		else if (current_state == ID && is_I_LDType)
			mem_read_inst_cnt <= mem_read_inst_cnt + 32'd1;
		else
			mem_read_inst_cnt <= mem_read_inst_cnt;
	end
	assign cpu_perf_cnt_2 = mem_read_inst_cnt;

	reg [31:0] mem_write_inst_cnt;
	always @(posedge clk) begin
		if (rst == 1'b1)
			mem_write_inst_cnt <= 32'd0;
		else if (current_state == ID && is_SType)
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
		else if (current_state == ID && (is_BType | is_I_JType | is_JType))
			bj_inst_cnt <= bj_inst_cnt + 32'd1;
		else
			bj_inst_cnt <= bj_inst_cnt;
	end
	assign cpu_perf_cnt_7 = bj_inst_cnt;

endmodule

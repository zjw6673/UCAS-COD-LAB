`timescale 10ns / 1ns

`define CACHE_SET	8
`define SET_ADDR_WIDTH	3
`define CACHE_WAY	4
`define TAG_LEN		24
`define LINE_LEN	256

module icache_top (
	input	      clk,
	input	      rst,
	
	//CPU interface
	/** CPU instruction fetch request to Cache: valid signal */
	input         from_cpu_inst_req_valid,
	/** CPU instruction fetch request to Cache: address (4 byte alignment) */
	input  [31:0] from_cpu_inst_req_addr,
	/** Acknowledgement from Cache: ready to receive CPU instruction fetch request */
	output        to_cpu_inst_req_ready,
	
	/** Cache responses to CPU: valid signal */
	output        to_cpu_cache_rsp_valid,
	/** Cache responses to CPU: 32-bit Instruction value */
	output [31:0] to_cpu_cache_rsp_data,
	/** Acknowledgement from CPU: Ready to receive Instruction */
	input         from_cpu_cache_rsp_ready,

	//Memory interface (32 byte aligned address)
	/** Cache sending memory read request: valid signal */
	output        to_mem_rd_req_valid,
	/** Cache sending memory read request: address (32 byte alignment) */
	output [31:0] to_mem_rd_req_addr,
	/** Acknowledgement from memory: ready to receive memory read request */
	input         from_mem_rd_req_ready,

	/** Memory return read data: valid signal of one data beat */
	input         from_mem_rd_rsp_valid,
	/** Memory return read data: 32-bit one data beat */
	input  [31:0] from_mem_rd_rsp_data,
	/** Memory return read data: if current data beat is the last in this burst data transmission */
	input         from_mem_rd_rsp_last,
	/** Acknowledgement from cache: ready to receive current data beat */
	output        to_mem_rd_rsp_ready
);

// TODO: Please add your I-Cache code here

	/* some parameters */
	// FSM state
	localparam WAIT     = 8'b00000001,
	           TAG_RD   = 8'b00000010,
	           CACHE_RD = 8'b00000100,
	           RESP     = 8'b00001000,
	           EVICT    = 8'b00010000,
	           MEM_RD   = 8'b00100000,
	           RECV     = 8'b01000000,
	           REFILL   = 8'b10000000;
	
	/* create inner signals */
	// FSM state registration
	reg  [                  7:0] currentStateReg, nextState;
	// handshake signal registration
	reg  [                 31:0] cpuAddrReg;
	reg  [                255:0] memBlockReg;
	// cache read
	wire                         cacheHit;
	wire                         rdValid [`CACHE_WAY - 1:0];
	wire [       `TAG_LEN - 1:0] rdTag   [`CACHE_WAY - 1:0];
	wire [      `LINE_LEN - 1:0] rdData  [`CACHE_WAY - 1:0];
	wire [                 31:0] returnData;
	assign to_cpu_cache_rsp_data = returnData;
	// mem read
	wire [                 31:0] memAddr;
	assign to_mem_rd_req_addr = memAddr;
	// eviction
	wire [`SET_ADDR_WIDTH - 1:0] evictIdx;  // choose a set to evict
	wire [     `CACHE_WAY - 1:0] evictEn;    // choose a way to evict
	wire [     `CACHE_WAY - 1:0] evictWay;
	wire                         evictValid;
	wire [       `TAG_LEN - 1:0] evictTag;
	wire [      `LINE_LEN - 1:0] evictData;
	// decode signal
	wire [`SET_ADDR_WIDTH - 1:0] reqIdx = cpuAddrReg[ 7:5];
	wire [       `TAG_LEN - 1:0] reqTag = cpuAddrReg[31:8];
	wire [`SET_ADDR_WIDTH + 1:0] reqOff = cpuAddrReg[ 4:0];

	/* instantiate hardwares */
	genvar i;
	generate
		for (i = 0; i < `CACHE_WAY; i = i + 1) begin : ways
			iway #(
				.TARRAY_DATA_WIDTH(`TAG_LEN),
				.DARRAY_DATA_WIDTH(`LINE_LEN),
				.ADDR_WIDTH(`SET_ADDR_WIDTH)
			) inst (
				.clk(clk),
				.rst(rst),
				.waddr(evictIdx),
				.raddr(reqIdx),
				.wen(evictEn[i]),
				.wvalid(evictValid),
				.wtag(evictTag),
				.wdata(evictData),
				.rvalid(rdValid[i]),
				.rtag(rdTag[i]),
				.rdata(rdData[i])
			);
		end
	endgenerate

	/* FSM */
	// section 1
	always @(posedge clk) begin
		if (rst)
			currentStateReg <= WAIT;
		else
			currentStateReg <= nextState;
	end
	// section 2
	always @(*) begin
		case(currentStateReg)
			WAIT:
				if (from_cpu_inst_req_valid)
					nextState = TAG_RD;
				else
					nextState = WAIT;
			TAG_RD:
				if (cacheHit)
					nextState = CACHE_RD;
				else
					nextState = EVICT;
			CACHE_RD:
				nextState = RESP;
			EVICT:
				nextState = MEM_RD;
			MEM_RD:
				if (from_mem_rd_req_ready)
					nextState = RECV;
				else
					nextState = MEM_RD;
			RECV:
				if (from_mem_rd_rsp_valid & from_mem_rd_rsp_last)
					nextState = REFILL;
				else
					nextState = RECV;
			REFILL:
				nextState = RESP;
			RESP:
				if (from_cpu_cache_rsp_ready)
					nextState = WAIT;
				else
					nextState = RESP;
			default: nextState = WAIT;
		endcase
	end

	/* cpu read signals */
	assign to_cpu_inst_req_ready  =  rst | (currentStateReg == WAIT);
	always @(posedge clk) begin // update cpuAddrReg after WAIT
		if (currentStateReg == WAIT)
			cpuAddrReg <= from_cpu_inst_req_addr;
		else
			cpuAddrReg <= cpuAddrReg;
	end

	/* cache hit signals */
	wire hit_way0 = (reqTag == rdTag[0] & rdValid[0]);
	wire hit_way1 = (reqTag == rdTag[1] & rdValid[1]);
	wire hit_way2 = (reqTag == rdTag[2] & rdValid[2]);
	wire hit_way3 = (reqTag == rdTag[3] & rdValid[3]);
	assign cacheHit = hit_way0 | hit_way1 | hit_way2 | hit_way3;

	/* mem read signals */
	// read request
	assign to_mem_rd_req_valid    = ~rst & (currentStateReg == MEM_RD);
	assign memAddr = {cpuAddrReg[31:5], 5'b0}; // align to 32 bytes
	// data receive
	assign to_mem_rd_rsp_ready    =  rst | (currentStateReg == RECV);
	always @(posedge clk) begin // update memBlockReg after RECV
		if (currentStateReg == RECV & from_mem_rd_rsp_valid)
			memBlockReg <= {from_mem_rd_rsp_data, memBlockReg[255:32]};
	end // store {data7, ..., data0} into memBlockReg

	/* cache write signals */
	assign evictIdx   = reqIdx;
	assign evictValid = (currentStateReg == REFILL);
	assign evictTag   = reqTag;
	assign evictData  = memBlockReg;
	assign evictEn    = (currentStateReg == REFILL) ? evictWay : 4'b0000;

	/* cpu write signals */
	assign to_cpu_cache_rsp_valid = ~rst & (currentStateReg == RESP);
	wire [`LINE_LEN - 1:0] returnBlock = (rdData[0] & {`LINE_LEN{hit_way0}})
	                                   | (rdData[1] & {`LINE_LEN{hit_way1}})
	                                   | (rdData[2] & {`LINE_LEN{hit_way2}})
	                                   | (rdData[3] & {`LINE_LEN{hit_way3}});
	assign returnData = returnBlock[ {reqOff, 3'b0} +: 32]; // [reqOff * 8, reqOff * 8 + 31]

	/* evict algorithm:  LRU approximation */
	// create an LRU for each set
	reg [2:0] LRU [7:0];
	// update LRU when rst or after RESP
	always @(posedge clk) begin
		if (rst) begin
			LRU[0] <= 3'b0;
			LRU[1] <= 3'b0;
			LRU[2] <= 3'b0;
			LRU[3] <= 3'b0;
			LRU[4] <= 3'b0;
			LRU[5] <= 3'b0;
			LRU[6] <= 3'b0;
			LRU[7] <= 3'b0;
		end else if (currentStateReg == RESP) begin // update binary tree
			LRU[reqIdx][2] <= (hit_way2 | hit_way3);
			LRU[reqIdx][1] <= (hit_way0 | hit_way1) ? hit_way1 : LRU[reqIdx][1];
			LRU[reqIdx][0] <= (hit_way2 | hit_way3) ? hit_way3 : LRU[reqIdx][0];
		end
	end
	// generate evictWay signal: use empty Way first, then leastUseWay
	wire leastUseWay0 =  LRU[reqIdx][2] &  LRU[reqIdx][1];
	wire leastUseWay1 =  LRU[reqIdx][2] & ~LRU[reqIdx][1];
	wire leastUseWay2 = ~LRU[reqIdx][2] &  LRU[reqIdx][0];
	wire leastUseWay3 = ~LRU[reqIdx][2] & ~LRU[reqIdx][0];
	wire [3:0] firstEmptyWay = ~rdValid[0] ? 4'b0001 :
		                         ~rdValid[1] ? 4'b0010 :
		                         ~rdValid[2] ? 4'b0100 :
		                         ~rdValid[3] ? 4'b1000 : 4'b0000;
	assign evictWay = (|firstEmptyWay) ? firstEmptyWay : {leastUseWay3, leastUseWay2, leastUseWay1, leastUseWay0};

endmodule


`timescale 10ns / 1ns

`define CACHE_SET	8
`define SET_ADDR_WIDTH	3
`define CACHE_WAY	4
`define TAG_LEN		24
`define LINE_LEN	256

module dcache_top (
	input	      clk,
	input	      rst,
  
	//CPU interface
	/** CPU memory/IO access request to Cache: valid signal */
	input         from_cpu_mem_req_valid,
	/** CPU memory/IO access request to Cache: 0 for read; 1 for write (when req_valid is high) */
	input         from_cpu_mem_req,
	/** CPU memory/IO access request to Cache: address (4 byte alignment) */
	input  [31:0] from_cpu_mem_req_addr,
	/** CPU memory/IO access request to Cache: 32-bit write data */
	input  [31:0] from_cpu_mem_req_wdata,
	/** CPU memory/IO access request to Cache: 4-bit write strobe */
	input  [ 3:0] from_cpu_mem_req_wstrb,
	/** Acknowledgement from Cache: ready to receive CPU memory access request */
	output        to_cpu_mem_req_ready,
		
	/** Cache responses to CPU: valid signal */
	output        to_cpu_cache_rsp_valid,
	/** Cache responses to CPU: 32-bit read data */
	output [31:0] to_cpu_cache_rsp_data,
	/** Acknowledgement from CPU: Ready to receive read data */
	input         from_cpu_cache_rsp_ready,
		
	//Memory/IO read interface
	/** Cache sending memory/IO read request: valid signal */
	output        to_mem_rd_req_valid,
	/** Cache sending memory read request: address
	  * 4 byte alignment for I/O read 
	  * 32 byte alignment for cache read miss */
	output [31:0] to_mem_rd_req_addr,
        /** Cache sending memory read request: burst length
	  * 0 for I/O read (read only one data beat)
	  * 7 for cache read miss (read eight data beats) */
	output [ 7:0] to_mem_rd_req_len,
        /** Acknowledgement from memory: ready to receive memory read request */
	input	      from_mem_rd_req_ready,

	/** Memory return read data: valid signal of one data beat */
	input	      from_mem_rd_rsp_valid,
	/** Memory return read data: 32-bit one data beat */
	input  [31:0] from_mem_rd_rsp_data,
	/** Memory return read data: if current data beat is the last in this burst data transmission */
	input	      from_mem_rd_rsp_last,
	/** Acknowledgement from cache: ready to receive current data beat */
	output        to_mem_rd_rsp_ready,

	//Memory/IO write interface
	/** Cache sending memory/IO write request: valid signal */
	output        to_mem_wr_req_valid,
	/** Cache sending memory write request: address
	  * 4 byte alignment for I/O write 
	  * 4 byte alignment for cache write miss
          * 32 byte alignment for cache write-back */
	output [31:0] to_mem_wr_req_addr,
        /** Cache sending memory write request: burst length
          * 0 for I/O write (write only one data beat)
          * 0 for cache write miss (write only one data beat)
          * 7 for cache write-back (write eight data beats) */
	output [ 7:0] to_mem_wr_req_len,
        /** Acknowledgement from memory: ready to receive memory write request */
	input         from_mem_wr_req_ready,

	/** Cache sending memory/IO write data: valid signal for current data beat */
	output        to_mem_wr_data_valid,
	/** Cache sending memory/IO write data: current data beat */
	output [31:0] to_mem_wr_data,
	/** Cache sending memory/IO write data: write strobe
	  * 4'b1111 for cache write-back 
	  * other values for I/O write and cache write miss according to the original CPU request*/ 
	output [ 3:0] to_mem_wr_data_strb,
	/** Cache sending memory/IO write data: if current data beat is the last in this burst data transmission */
	output        to_mem_wr_data_last,
	/** Acknowledgement from memory/IO: ready to receive current data beat */
	input	      from_mem_wr_data_ready
);

  // TODO: Please add your D-Cache code here

	/* FSM state encoding */
	localparam WAIT    = 16'b0000000000000001,
	           RD_TAG  = 16'b0000000000000010,
	           WR_CCH  = 16'b0000000000000100,
	           RD_CCH  = 16'b0000000000001000,
	           RSP_CCH = 16'b0000000000010000,
	           EVICT   = 16'b0000000000100000,
	           WRR_MEM = 16'b0000000001000000,
	           WR_MEM  = 16'b0000000010000000,
	           RDR_MEM = 16'b0000000100000000,
	           RD_MEM  = 16'b0000001000000000,
	           REFILL  = 16'b0000010000000000,
	           WRR_BY  = 16'b0000100000000000,
	           WR_BY   = 16'b0001000000000000,
	           RDR_BY  = 16'b0010000000000000,
	           RD_BY   = 16'b0100000000000000,
	           RSP_BY  = 16'b1000000000000000;

	/* create inner signals */
	// FSM state registration
	reg [15:0]                   currentStateReg, nextState;
	// handshake signal registration
	reg                          cpuReqReg; // 0-read, 1-write
	reg [           31:0]        cpuAddrReg;
	reg [           31:0]        cpuWdataReg;
	reg [            3:0]        cpuWstrbReg;
	reg [`LINE_LEN - 1:0]        memReadBlockReg;
	reg [           31:0]        memReadWordReg;
	// parse input cpuAddr
	wire [`SET_ADDR_WIDTH - 1:0] reqIdx = cpuAddrReg[ 7:5];
	wire [       `TAG_LEN - 1:0] reqTag = cpuAddrReg[31:8];
	wire [`SET_ADDR_WIDTH + 1:0] reqOff = cpuAddrReg[ 4:0];
	wire                         isBypath;
	// cache hit situation
	wire                         cacheHit;
	wire [     `CACHE_WAY - 1:0] hitWay;        // the way that gets hit (one-hot)
	wire                         isDirty;       // wether hitWay is dirty
	// cache read
	wire [     `CACHE_WAY - 1:0] rdValid;
	wire [     `CACHE_WAY - 1:0] rdDirty;
	wire [       `TAG_LEN - 1:0] rdTag   [`CACHE_WAY - 1:0];
	wire [      `LINE_LEN - 1:0] rdData  [`CACHE_WAY - 1:0];
	wire [                 31:0] hitData;    // read data to return to cpu
	// cache evict & write
	wire [     `CACHE_WAY - 1:0] evictWay;      // selected way to evict
	wire [                 31:0] modifiedData;  // modified data to write to cache
	wire [      `LINE_LEN - 1:0] modifiedBlock; // modified block with modified data inside
	wire [     `CACHE_WAY - 1:0] evictEn;       // one-hot encoded wen for way3 ~ way0
	wire                         evictValid, evictDirty;
	wire [       `TAG_LEN - 1:0] evictTag;
	wire [      `LINE_LEN - 1:0] evictData;

	/* instantiate hardwares */
	genvar i;
	generate
		for (i = 0; i < `CACHE_WAY; i = i + 1) begin : ways
			dway #(
				.TARRAY_DATA_WIDTH(`TAG_LEN),
				.DARRAY_DATA_WIDTH(`LINE_LEN),
				.ADDR_WIDTH(`SET_ADDR_WIDTH)
			) inst (
				.clk(clk),
				.rst(rst),
				.waddr(reqIdx),
				.raddr(reqIdx),
				.wen(evictEn[i]),
				.wvalid(evictValid),
				.wdirty(evictDirty),
				.wtag(evictTag),
				.wdata(evictData),
				.rvalid(rdValid[i]),
				.rdirty(rdDirty[i]),
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
			WAIT: begin
				if (from_cpu_mem_req_valid)
					nextState = RD_TAG;
				else
					nextState = WAIT;
			end
			RD_TAG: begin
				if (isBypath & cpuReqReg)
					nextState = WRR_BY;
				else if (isBypath & ~cpuReqReg)
					nextState = RDR_BY;
				else if (cacheHit & cpuReqReg)
					nextState = WR_CCH;
				else if (cacheHit & ~cpuReqReg)
					nextState = RD_CCH;
				else
					nextState = EVICT;
			end
			WR_CCH: begin
				nextState = WAIT;
			end
			RD_CCH: begin
				nextState = RSP_CCH;
			end
			RSP_CCH: begin
				if (from_cpu_cache_rsp_ready)
					nextState = WAIT;
				else
					nextState = RSP_CCH;
			end
			EVICT: begin
				if (isDirty)
					nextState = WRR_MEM;
				else
					nextState = RDR_MEM;
			end
			WRR_MEM: begin
				if (from_mem_wr_req_ready)
					nextState = WR_MEM;
				else
					nextState = WRR_MEM;
			end
			WR_MEM: begin
				if (from_mem_wr_data_ready & to_mem_wr_data_last)
					nextState = RDR_MEM;
				else
					nextState = WR_MEM;
			end
			RDR_MEM: begin
				if (from_mem_rd_req_ready)
					nextState = RD_MEM;
				else
					nextState = RDR_MEM;
			end
			RD_MEM: begin
				if (from_mem_rd_rsp_valid & from_mem_rd_rsp_last)
					nextState = REFILL;
				else
					nextState = RD_MEM;
			end
			REFILL: begin
				nextState = cpuReqReg ? WR_CCH : RD_CCH;
			end
			WRR_BY: begin
				if (from_mem_wr_req_ready)
					nextState = WR_BY;
				else
					nextState = WRR_BY;
			end
			WR_BY: begin
				if (from_mem_wr_data_ready & to_mem_wr_data_last)
					nextState = WAIT;
				else
					nextState = WR_BY;
			end
			RDR_BY: begin
				if (from_mem_rd_req_ready)
					nextState = RD_BY;
				else
					nextState = RDR_BY;
			end
			RD_BY: begin
				if (from_mem_rd_rsp_valid & from_mem_rd_rsp_last)
					nextState = RSP_BY;
				else
					nextState = RD_BY;
			end
			RSP_BY: begin
				if (from_cpu_cache_rsp_ready)
					nextState = WAIT;
				else
					nextState = RSP_BY;
			end
			default: nextState = WAIT;
		endcase
	end

	/* WAIT state */
	assign to_cpu_mem_req_ready = rst
	                            | (currentStateReg == WAIT & from_cpu_mem_req_valid & ~from_cpu_mem_req) // read req
	                            | (currentStateReg == WR_BY & from_mem_wr_data_ready & to_mem_wr_data_last) // bypass write
	                            | (currentStateReg == WR_CCH); // cache write
	always @(posedge clk) begin // registrate cpu input after WAIT
		if (currentStateReg == WAIT) begin
			cpuReqReg   <= from_cpu_mem_req;
			cpuAddrReg  <= from_cpu_mem_req_addr;
			cpuWdataReg <= from_cpu_mem_req_wdata;
			cpuWstrbReg <= from_cpu_mem_req_wstrb;
		end else begin
			cpuReqReg   <= cpuReqReg;
			cpuAddrReg  <= cpuAddrReg;
			cpuWdataReg <= cpuWdataReg;
			cpuWstrbReg <= cpuWstrbReg;
		end
	end

	/* TAG_RD state: see if addr legal & in cache */
	// bypath: 0x00 ~ 0x1F OR above 0x4000_0000
	assign isBypath = (~|cpuAddrReg[31:5]) | (|cpuAddrReg[31:30]);
	// search for hit in cache
	wire   hit_way0 = (rdValid[0] & rdTag[0] == reqTag);
	wire   hit_way1 = (rdValid[1] & rdTag[1] == reqTag);
	wire   hit_way2 = (rdValid[2] & rdTag[2] == reqTag);
	wire   hit_way3 = (rdValid[3] & rdTag[3] == reqTag);
	assign hitWay   = {hit_way3, hit_way2, hit_way1, hit_way0};
	assign cacheHit = |hitWay;
	assign isDirty  = |(rdDirty & evictWay);

	/* RD_CCH state: read cache */
	// assume that there is and only is one way gets hit now ( else evict and refill)
	wire [`LINE_LEN - 1:0] hitBlock = (rdData[0] & {`LINE_LEN{hit_way0}})
	                                | (rdData[1] & {`LINE_LEN{hit_way1}})
	                                | (rdData[2] & {`LINE_LEN{hit_way2}})
	                                | (rdData[3] & {`LINE_LEN{hit_way3}});
	assign hitData = hitBlock[ {reqOff, 3'b0} +: 32]; // [reqOff * 8, reqOff * 8 + 31]

	/* respond to CPU */
	// universal signal
	assign to_cpu_cache_rsp_valid = ~rst & (currentStateReg == RSP_CCH | currentStateReg == RSP_BY);
	assign to_cpu_cache_rsp_data  = isBypath ? memReadWordReg : hitData;

	/* cache EVICTION */
	// WR_CCH state
	assign modifiedData = { // process wdata and wstrb
			{ ({8{cpuWstrbReg[3]}} & cpuWdataReg[31:24]) | ({8{~cpuWstrbReg[3]}} & hitData[31:24]) },
			{ ({8{cpuWstrbReg[2]}} & cpuWdataReg[23:16]) | ({8{~cpuWstrbReg[2]}} & hitData[23:16]) },
			{ ({8{cpuWstrbReg[1]}} & cpuWdataReg[15: 8]) | ({8{~cpuWstrbReg[1]}} & hitData[15: 8]) },
			{ ({8{cpuWstrbReg[0]}} & cpuWdataReg[ 7: 0]) | ({8{~cpuWstrbReg[0]}} & hitData[ 7: 0]) }
		};
	assign modifiedBlock = ({hitBlock[`LINE_LEN - 1: 32], modifiedData                 } & {`LINE_LEN{reqOff[4:2] == 3'b000}})
	                     | ({hitBlock[`LINE_LEN - 1: 64], modifiedData, hitBlock[ 31:0]} & {`LINE_LEN{reqOff[4:2] == 3'b001}})
	                     | ({hitBlock[`LINE_LEN - 1: 96], modifiedData, hitBlock[ 63:0]} & {`LINE_LEN{reqOff[4:2] == 3'b010}})
	                     | ({hitBlock[`LINE_LEN - 1:128], modifiedData, hitBlock[ 95:0]} & {`LINE_LEN{reqOff[4:2] == 3'b011}})
	                     | ({hitBlock[`LINE_LEN - 1:160], modifiedData, hitBlock[127:0]} & {`LINE_LEN{reqOff[4:2] == 3'b100}})
	                     | ({hitBlock[`LINE_LEN - 1:192], modifiedData, hitBlock[159:0]} & {`LINE_LEN{reqOff[4:2] == 3'b101}})
	                     | ({hitBlock[`LINE_LEN - 1:224], modifiedData, hitBlock[191:0]} & {`LINE_LEN{reqOff[4:2] == 3'b110}})
	                     | ({                             modifiedData, hitBlock[223:0]} & {`LINE_LEN{reqOff[4:2] == 3'b111}});
	// REFILL state
	// univeral signal
	assign evictEn    = (currentStateReg == WR_CCH) ? hitWay  :
	                    (currentStateReg == REFILL) ? evictWay:
	                                                  4'b0000 ;
	assign evictValid = 1'b1;
	assign evictDirty = (currentStateReg == WR_CCH);
	assign evictTag   = reqTag;
	assign evictData  = (currentStateReg == WR_CCH) ? modifiedBlock  :
	                                                  memReadBlockReg; // used in REFILL

	/* mem write req */
	// universal signal
	assign to_mem_wr_req_valid = ~rst & (currentStateReg == WRR_MEM | currentStateReg == WRR_BY);
	assign to_mem_wr_req_addr = ( {rdTag[0], reqIdx, 5'b0} & {32{~isBypath & evictWay[0]}} )
	                          | ( {rdTag[1], reqIdx, 5'b0} & {32{~isBypath & evictWay[1]}} )
	                          | ( {rdTag[2], reqIdx, 5'b0} & {32{~isBypath & evictWay[2]}} )
	                          | ( {rdTag[3], reqIdx, 5'b0} & {32{~isBypath & evictWay[3]}} )
	                          | (               cpuAddrReg & {32{isBypath}});
	assign to_mem_wr_req_len = {5'b0, {3{~isBypath}}};

	/* mem write rsp */
	// write 8 words on dirty eviction
	wire [`LINE_LEN - 1:0] BlockToEvict = (rdData[0] & {`LINE_LEN{evictWay[0]}})
	                                    | (rdData[1] & {`LINE_LEN{evictWay[1]}})
	                                    | (rdData[2] & {`LINE_LEN{evictWay[2]}})
	                                    | (rdData[3] & {`LINE_LEN{evictWay[3]}});
	reg [`LINE_LEN - 1:0] wordToEvictShifter;
	always @(posedge clk) begin
		if (currentStateReg == WRR_MEM) // load block in WRR_MEM
			wordToEvictShifter <= BlockToEvict;
		else if (currentStateReg == WR_MEM & from_mem_wr_data_ready) // shift to upate work to send
			wordToEvictShifter <= {32'd0, wordToEvictShifter[255:32]};
	end
	// write 1 word on bypass read
	// universal signal
	reg [7:0] memWriteShifter; // a shifter to generate last signal
	always @(posedge clk) begin
		if (currentStateReg == WRR_MEM)
			memWriteShifter <= {1'b1, 7'b0};
		else if (currentStateReg == WRR_BY)
			memWriteShifter <= 8'd1;
		else if ((currentStateReg == WR_MEM | currentStateReg == WR_BY) & from_mem_wr_data_ready)
			memWriteShifter <= {1'b0, memWriteShifter[7:1]};
		else
			memWriteShifter <= memWriteShifter;
	end

	assign to_mem_wr_data_valid = ~rst & (currentStateReg == WR_MEM | currentStateReg == WR_BY);
	assign to_mem_wr_data_last  = memWriteShifter[0];
	assign to_mem_wr_data       = isBypath ? cpuWdataReg : wordToEvictShifter[31:0];
	assign to_mem_wr_data_strb  = isBypath ? cpuWstrbReg : 4'b1111;

	/* mem read req */
	// universal signal
	assign to_mem_rd_req_valid      = ~rst & (currentStateReg == RDR_MEM | currentStateReg == RDR_BY);
	assign to_mem_rd_req_addr[31:5] = {reqTag, reqIdx};
	assign to_mem_rd_req_addr[4:0]  = reqOff & {5{isBypath}};
	assign to_mem_rd_req_len        = {5'd0, {3{~isBypath}}};

	/* mem read rsp */
	// RD_MEM state: read a block
	always @(posedge clk) begin // update memReadBlockReg after RD_MEM
		if (currentStateReg == RD_MEM & from_mem_rd_rsp_valid)
			memReadBlockReg <= {from_mem_rd_rsp_data, memReadBlockReg[255:32]};
		else
			memReadBlockReg <= memReadBlockReg;
	end
	// RD_BY state: read a word
	always @(posedge clk) begin
		if (currentStateReg == RD_BY & from_mem_rd_rsp_valid)
			memReadWordReg <= from_mem_rd_rsp_data;
		else
			memReadWordReg <= memReadWordReg;
	end
	// universal signal
	assign to_mem_rd_rsp_ready = rst | (currentStateReg == RD_MEM | currentStateReg == RD_BY);

	/* evict algorithm: LRU approximation */
	// create an LRU for each set
	reg [2:0] LRU [7:0];
	// update LRU when rst or after RD_CCH and WR_CCH
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
		end else if (currentStateReg == RD_CCH | currentStateReg == WR_CCH) begin // update binary tree according to hitway signal
			LRU[reqIdx][2] <= (hitWay[2] | hitWay[3]);
			LRU[reqIdx][1] <= (hitWay[0] | hitWay[1]) ? hitWay[1] : LRU[reqIdx][1];
			LRU[reqIdx][0] <= (hitWay[2] | hitWay[3]) ? hitWay[3] : LRU[reqIdx][0];
		end
	end
	// generate evictWay signal: evict empty Way first, then leastUseWay
	wire [3:0] lruWay = {
		~LRU[reqIdx][2] & ~LRU[reqIdx][0], // way3
		~LRU[reqIdx][2] &  LRU[reqIdx][0], // way2
		 LRU[reqIdx][2] & ~LRU[reqIdx][1], // way1
		 LRU[reqIdx][2] &  LRU[reqIdx][1]  // way0
	};
	wire [3:0] firstEmptyWay = ~rdValid[0] ? 4'b0001 :
	                           ~rdValid[1] ? 4'b0010 :
	                           ~rdValid[2] ? 4'b0100 :
	                           ~rdValid[3] ? 4'b1000 : 4'b0000;
	assign evictWay = (|firstEmptyWay) ? firstEmptyWay : lruWay;

endmodule


`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Xu Zhang (zhangxu415@mails.ucas.ac.cn)
// 
// Create Date: 06/14/2018 11:39:09 AM
// Design Name: 
// Module Name: dma_core
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module engine_core #(
	parameter integer  DATA_WIDTH       = 32
)
(
	input    clk,
	input    rst,
	
	output [31:0]       src_base,
	output [31:0]       dest_base,
	output [31:0]       tail_ptr,
	output [31:0]       head_ptr,
	output [31:0]       dma_size,
	output [31:0]       ctrl_stat,

	input  [31:0]       reg_wr_data,
	input  [ 5:0]       reg_wr_en,
  
	output              intr,

	output [31:0]       rd_req_addr,
	output [ 4:0]       rd_req_len,
	output              rd_req_valid,
	
	input               rd_req_ready,
	input  [31:0]       rd_rdata,
	input               rd_last,
	input               rd_valid,
	output              rd_ready,
	
	output [31:0]       wr_req_addr,
	output [ 4:0]       wr_req_len,
	output              wr_req_valid,
	input               wr_req_ready,
	output [31:0]       wr_data,
	output              wr_valid,
	input               wr_ready,
	output              wr_last,
	
	output              fifo_rden,
	output [31:0]       fifo_wdata,
	output              fifo_wen,
	
	input  [31:0]       fifo_rdata,
	input               fifo_is_empty,
	input               fifo_is_full
);
	// TODO: Please add your logic design here

	/* state encodings */
	localparam RD_IDLE = 3'b001,
	           RD_REQ  = 3'b010,
	           RD      = 3'b100,
	           WR_IDLE = 3'b001,
	           WR_REQ  = 3'b010,
	           WR      = 3'b100;
	reg [2:0] rdCurrentState, rdNextState;
	reg [2:0] wrCurrentState, wrNextState;

	/* control registers */
	reg [31:0] srcBaseReg;
	reg [31:0] destBaseReg;
	reg [31:0] tailPtrReg;
	reg [31:0] headPtrReg;
	reg [31:0] dmaSizeReg;
	reg [31:0] ctrlStatReg;
	assign src_base  = srcBaseReg;
	assign dest_base = destBaseReg;
	assign tail_ptr  = tailPtrReg;
	assign head_ptr  = headPtrReg;
	assign dma_size  = dmaSizeReg;
	assign ctrl_stat = ctrlStatReg;
	// parse the ctrlStatReg
	assign intr = ctrlStatReg[31];
	wire   en   = ctrlStatReg[0];

	/* burst count control */
	reg  [31:0] rdBurstCnt, wrBurstCnt; // keep track of progress
	// each burst transmits 32 bytes, encoded by the last 5 bits
	wire [31:0] nrFullBurst = {5'b0, dmaSizeReg[31:5]};
	wire [31:0] nrPartBurst = {31'b0, |dmaSizeReg[4:0]}; // 0 or 1
	wire [31:0] nrBurst     = nrFullBurst + nrPartBurst;
	// rdBurstCnt and wrBurstCnt counts from 0 to nrBurst-1, and finished while
	// they are equal
	wire transmitFinish = (wrCurrentState == WR_REQ) & (wrBurstCnt == nrBurst) & (rdBurstCnt == nrBurst);
	// update rdBurstCnt and wrBurstCnt
	always @(posedge clk) begin
		if (rst)
			rdBurstCnt <= 32'b0;
		else if (rdCurrentState == RD_IDLE & wrCurrentState == WR_IDLE)
			rdBurstCnt <= 32'b0;
		else begin // accumulate
			if (rdCurrentState == RD & rd_valid & rd_ready & rd_last)
				rdBurstCnt <= rdBurstCnt + 32'b1;
			else
				rdBurstCnt <= rdBurstCnt;
		end
	end
	always @(posedge clk) begin
		if (rst)
			wrBurstCnt <= 32'b0;
		else if (rdCurrentState == RD_IDLE & wrCurrentState == WR_IDLE)
			wrBurstCnt <= 32'b0;
		else begin // accumulate
			if (wrCurrentState == WR & wr_ready & wr_valid & wr_last)
				wrBurstCnt <= wrBurstCnt + 32'b1;
			else
				wrBurstCnt <= wrBurstCnt;
		end
	end

	/* burst length control */
	wire [4:0] nrFullWords = {2'b0, dmaSizeReg[4:2]};
	wire [4:0] nrFracWords = {4'b0, |dmaSizeReg[1:0]};
	wire [4:0] lastBurstLen = nrFullWords + nrFracWords - 5'b1; // unit: words
	assign rd_req_len = (nrPartBurst[0] & (rdBurstCnt == (nrBurst - 32'b1))) ? lastBurstLen : 5'd7;
	assign wr_req_len = (nrPartBurst[0] & (wrBurstCnt == (nrBurst - 32'b1))) ? lastBurstLen : 5'd7;
	
	/* FSM for read */
	always @(posedge clk) begin
		if (rst)
			rdCurrentState <= RD_IDLE;
		else
			rdCurrentState <= rdNextState;
	end
	always @(*) begin
		case (rdCurrentState)
			RD_IDLE: begin
				if (en & (wrCurrentState == WR_IDLE) & headPtrReg != tailPtrReg)
					rdNextState = RD_REQ;
				else
					rdNextState = RD_IDLE;
			end
			RD_REQ: begin
				if (rd_req_ready & rd_req_valid)
					rdNextState = RD;
				else if (rdBurstCnt == nrBurst) // finished reading whole dma-size
					rdNextState = RD_IDLE;
				else
					rdNextState = RD_REQ;
			end
			RD: begin
				if (rd_valid & rd_ready & rd_last)
					rdNextState = RD_REQ;
				else
					rdNextState = RD;
			end
			default:
				rdNextState = RD_IDLE;
		endcase
	end

	/* FSM for write */
	always @(posedge clk) begin
		if (rst)
			wrCurrentState <= WR_IDLE;
		else
			wrCurrentState <= wrNextState;
	end
	always @(*) begin
		case (wrCurrentState)
			WR_IDLE: begin
				if (en & headPtrReg != tailPtrReg & !fifo_is_empty) // no need to wait for reading to end, start as long as fifo non-empty
					wrNextState = WR_REQ;
				else
					wrNextState = WR_IDLE;
			end
			WR_REQ: begin
				if (wr_req_ready & wr_req_valid)
					wrNextState = WR;
				else if (wrBurstCnt == nrBurst)
					wrNextState = WR_IDLE;
				else
					wrNextState = WR_REQ;
			end
			WR: begin
				if (wr_valid & wr_ready & wr_last)
					wrNextState = WR_REQ;
				else
					wrNextState = WR;
			end
			default:
				wrNextState = WR_IDLE;
		endcase
	end

	/* interact with CPU */
	always @(posedge clk) begin
		if (rst) begin
			srcBaseReg  <= 32'b0;
			destBaseReg <= 32'b0;
			tailPtrReg  <= 32'b0;
			headPtrReg  <= 32'b0;
			dmaSizeReg  <= 32'b0;
			ctrlStatReg <= 32'b0;
		end else if (en & transmitFinish) begin // send intr to CPU
			tailPtrReg <= tailPtrReg + dmaSizeReg;
			ctrlStatReg[31] <= 1'b1;
		end else begin // receive control from CPU
			if (reg_wr_en[0])  srcBaseReg  <= reg_wr_data;
			if (reg_wr_en[1])  destBaseReg <= reg_wr_data;
			if (reg_wr_en[2])  tailPtrReg  <= reg_wr_data;
			if (reg_wr_en[3])  headPtrReg  <= reg_wr_data;
			if (reg_wr_en[4])  dmaSizeReg  <= reg_wr_data;
			if (reg_wr_en[5])  ctrlStatReg <= reg_wr_data;
		end
	end

	/* read request */
	assign rd_req_valid = (rdCurrentState == RD_REQ) & ~fifo_is_full & (rdBurstCnt != nrBurst);
	reg [31:0] readAddrReg;
	always @(posedge clk) begin
		if (rdCurrentState == RD_IDLE & wrCurrentState == WR_IDLE & headPtrReg != tailPtrReg) // init addr after IDLE
			readAddrReg <= srcBaseReg + tailPtrReg;
		else if ((rdCurrentState == RD) & rd_ready & rd_valid & rd_last) begin // update addr after each burst
			if (rdBurstCnt == (nrBurst - 32'b1)) // the last burst
				readAddrReg <= readAddrReg + {27'b0, dmaSizeReg[4:0]};
			else
				readAddrReg <= readAddrReg + 32'd32;
		end
	end
	assign rd_req_addr = readAddrReg;

	/* read rsp */
	assign rd_ready = (rdCurrentState == RD) & ~fifo_is_full;
	// store the data to FIFO
	assign fifo_wen = rd_ready & rd_valid;
	assign fifo_wdata = rd_rdata;

	/* write request */
	assign wr_req_valid = (wrCurrentState == WR_REQ) & ~fifo_is_empty & (wrBurstCnt != nrBurst);
	reg [31:0] writeAddrReg;
	always @(posedge clk) begin
		if (rdCurrentState == RD_IDLE & wrCurrentState == WR_IDLE & headPtrReg != tailPtrReg) // init addr after IDLE
			writeAddrReg <= destBaseReg + tailPtrReg;
		else if ((wrCurrentState == WR) & wr_ready & wr_valid & wr_last) begin // update addr after each burst
			if (wrBurstCnt == (nrBurst - 32'd1))
				writeAddrReg <= writeAddrReg + {27'b0, dmaSizeReg[4:0]};
			else
				writeAddrReg <= writeAddrReg + 32'd32;
		end
	end
	assign wr_req_addr = writeAddrReg;

	/* write rsp */
	// read data from FIFO, data will return in the next clk cycle!
	assign fifo_rden = (wrCurrentState == WR) & ~fifo_is_empty & wr_ready;

	reg wrValidReg; // delay one clk cycle
	always @(posedge clk) begin
		wrValidReg <= fifo_rden;
	end
	assign wr_valid = wrValidReg;

	assign wr_data = fifo_rdata; // FIFO will hold the data, so no need for registration

	// generate last signal
	reg [7:0] lastGenerator;
	always @(posedge clk) begin
		if (wr_req_ready & wr_req_valid) // init lastGenerator when entering WR state
			lastGenerator <= (8'b1 << (wr_req_len + 1));
		else if (fifo_rden) // shift whenever fifo is read
			lastGenerator <= {1'b0, lastGenerator[7:1]};
		else
			lastGenerator <= lastGenerator;
	end
	assign wr_last = lastGenerator[0];

endmodule


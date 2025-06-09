module mul(
	input         clk,
	input         rst,
	input  [31:0] a,
	input  [31:0] b,
	input         valid,
	output        ready,
	output [63:0] result
);

localparam WAIT  = 4'b0001,
           ADD   = 4'b0010, // from Q_n and Q_{n+1} generate X or X comp to ADDER, then generate result
           SHIFT = 4'b0100, // shift AQ right one bit
           RSP   = 4'b1000;

reg [3:0] currentState, nextState;

reg  [65:0] AQ;
reg  [32:0] X;
wire [32:0] X_cmp;
reg  [ 4:0] cnt;
wire [32:0] addNum;

always @(posedge clk) begin
	if (rst)
		currentState <= WAIT;
	else
		currentState <= nextState;
end

always @(*) begin
	case (currentState)
		WAIT: begin
			if (valid)
				nextState = ADD;
			else
				nextState = WAIT;
		end
		ADD: begin
			if (cnt == 5'b0)
				nextState = RSP;
			else
				nextState = SHIFT;
		end
		SHIFT: begin
			nextState = ADD;
		end
		RSP: begin
			nextState = WAIT;
		end
		default: nextState = WAIT;
	endcase
end

/* assign registers */
always @(posedge clk) begin
	if (rst)
		X <= 33'b0;
	else if (currentState == WAIT)
		X <= {a[31], a}; // two sign bits
	else
		X <= X;
end

always @(posedge clk) begin
	if (rst)
		AQ <= 66'b0;
	else if (currentState ==  WAIT)
		AQ <= {33'd0, b, 1'b0}; // append 0 at the end
	else if (currentState == ADD)
		AQ <= {(AQ[65:33] + addNum), AQ[32:0]}; // add
	else if (currentState == SHIFT)
		AQ <= {AQ[65], AQ[65:1]}; // shift right
	else
		AQ <= AQ;
end

always @(posedge clk) begin
	if (rst)
		cnt <= 5'b0;
	else if (currentState == WAIT)
		cnt <= 5'd31;
	else if (currentState == ADD)
		cnt <= cnt - 1'b1;
	else
		cnt <= cnt;
end

assign X_cmp = ~X + 33'b1;

/* ADD state */
assign addNum = (~AQ[1] &  AQ[0]) ? X     :
                ( AQ[1] & ~AQ[0]) ? X_cmp : 33'b0;

/* RSP state */
assign ready = (currentState == RSP) ? 1'b1 : 1'b0;
assign result = AQ[65:2];

endmodule

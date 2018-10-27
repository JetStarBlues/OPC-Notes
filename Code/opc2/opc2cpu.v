/*
	bbbb xxoo : oooooooo
	 \       \        \
	  \       \________\______  10 bit operand
	   \______________________   4 bit opcode

	Instructions can take up 1 (00xx) or 2 bytes
*/

/*
	ADC  = 0000
	NOT  = 0001
	AND  = 0010
	AXB  = 0011
	JPC  = 0100
	JPZ  = 0101
	STA  = 0110
	JAL  = 0111
	LDBI = 1000
	LDB  = 1001
	STAP = 1010
	   . = 1011
	LDBP = 1100
	   . = 1101
	   . = 1110
	HALT = 1111 (simulation only)
*/
module opc2cpu (

	input       reset_b
	input       clk,
	output[9:0] address,
	output      rnw,
	inout[7:0]  data,
);

	parameter FETCH0 = 0,
	          FETCH1 = 1,
	          RDMEM  = 2,
	          RDMEM2 = 3,
	          EXEC   = 4;

	parameter ADC  = 4'b0000,  // add with carry
              NOT  = 4'b0001,
              AND  = 4'b0010,
              AXB  = 4'b0011,  // swap A and B registers
              JPC  = 4'b0100,  // jump if carry
              JPZ  = 4'b0101,  // jump if zero
              STA  = 4'b0110,  // store accumulator
              JAL  = 4'b0111,  // jump and link? PC is swapped with A and B registers
              LDBI = 4'b1000,
              LDB  = 4'b1001,  // load B register
              STAP = 4'b1010,
              LDBP = 4'b1100;

	reg [9:0] OR_q,   // operand
	          PC_q;   // program couner
	reg [7:0] ACC_q,  // accumulator
	          B_q;    // B register
	reg [3:0] IR_q;   // instruction egister / opcode
	reg [2:0] FSM_q;  // finite state machine
	reg       C_q;    // carry

	wire writeback_w = ( ( FSM_q == EXEC ) &&
		                 ( IR_q == STA || IR_q == STAP )
		               ) & reset_b;

	assign rnw = ~ writeback_w;

	// if writeback, databus = accumulator else high impedance?
	assign data = writeback_w ? ACC_q : 8'bz;
	// if writeback or readMem instr, address = operand else address = PC
	assign address = ( writeback_w || FSM_q == RDMEM || FSM_q == RDMEM2 ) ? OR_q : PC_q;

	// Microinstruction select
	always @ ( posedge clk or negedge reset_b )

		if ( ! reset_b )

			FSM_q <= FETCH0;

		else

			/*
			   FETCH0 -> EXEC
			          -> FETCH1 -> EXEC
			                    -> RDMEM -> RDMEM2 -> EXEC
			                             -> EXEC
			*/

			case ( FSM_q )

				FETCH0 : FSM_q <= ( data[7] || data[6] ) ? FETCH1 : EXEC;      // 1 byte instrs go direct to EXEC, otherwise get second byte
				FETCH1 : FSM_q <= ( IR_q[3] && IR_q != LDBI ) ? RDMEM : EXEC;  // ??? read Mem[ immediate ]
				RDMEM  : FSM_q <= IR_q[2] ? RDMEM2 : EXEC;                     // ??? read Mem[ Mem[ immediate ] ]
				RDMEM2 : FSM_q <= EXEC;
				EXEC   : FSM_q <= FETCH0;

			endcase

	// Fetch and Execute
	always @ ( posedge clk )
	begin

		IR_q      <= IR_q;       // default case
		OR_q[9:8] <= OR_q[9:8];  // default case

		/* LSNibble of IR_q on FETCH1, used as upper nibble of operand.
		   Needs to be zeroed for pointer writes/reads */
		if ( FSM_q == FETCH0 ) begin

			IR_q      <= data[7:4];  // upper 4 bits of databus

			OR_q[9:8] <= data[1:0];  // lower 2 bits of databus

		end

		else if ( FSM_q == RDMEM )

			OR_q[9:8] <= 2'b00;

		OR_q[7:0] <= data;  // Always mirrors databus (t-1?). Whether value acted on depends on instruction
		                    // OR_q is dont care in FETCH0 and at end of EXEC

		if ( FSM_q == EXEC )

			case ( IR_q )

				AXB  : { B_q, ACC_q } <= {
				                           ACC_q,
				                           B_q
				                         };

				AND  : { C_q, ACC_q } <= {
				                           1'b0,
				                           ACC_q & B_q
				                         };
				NOT  : ACC_q          <= ~ ACC_q;
				ADC  : { C_q, ACC_q } <= ACC_q + B_q + C_q;

				JAL  : { B_q, ACC_q } <= {                   // place PC value in B and A registers
				                           6'b000000,
				                           PC_q
				                         };

				LDB  : B_q            <= OR_q[7:0];
				LDBP : B_q            <= OR_q[7:0];
				LDBI : B_q            <= OR_q[7:0];

			endcase
	end

	// Set program counter
	always @ ( posedge clk or negedge reset_b )

		// On reset start execution at 0x100 to leave page zero clear for variables
		if ( ! reset_b )

			PC_q <= 10'h100;

		// Increment program counter
		else if ( FSM_q == FETCH0 || FSM_q == FETCH1 )

			PC_q <= PC_q + 1;

		// Jump
		else if ( FSM_q == EXEC )

			case ( IR_q )

				JPC : PC_q <= ( C_q ) ? OR_q : PC_q;  // jump if carry
				JAL : PC_q <= {                       // jump to address stored in B and A registers
				                B_q[1:0],
				                ACC_q
				              };

				// default : PC_q <= PC_q;

			endcase

endmodule

/*
	bbbbb  ooo : oooooooo
	 \       \        \_______   8 bit operand for Immediate/Implied Instructions, or
	  \       \________\______  11 bit operand for Direct/Indirect Instructions
	   \______________________   5 bit opcode


	Insruction variants:

		LDA   -> Accumulator = byte2                // implied immediate
		LDA.i -> Accumulator = Mem[ byte2 ]         // direct immediate
		LDA.p -> Accumulator = Mem[ Mem[ byte2 ] ]  // indirect immediate

	Each instruction takes up 2 bytes

	Entering subroutine:
	  When JSR, PC value (returnLoc) placed in link(upper 3) and accumulator(lower 8).
	  Up to program to save this return address.
	   > STA can be used to save part in accumulator?
	   > LXA can be used to save part in link register...

	Leaving subroutine:
	  Up to program to set PC = returnLoc
	   > LXA to get upper 3 bits
	   > LDA to get lower 8 bits
	  When RTS, PC value = link(upper 3) and accumulator(lower 8)
*/

/*
	ANDI = 00000
	LDAI = 00001
	NOTI = 00010
	ADDI = 00011
	   . = 00100
	   . = 00101
	   . = 00110
	   . = 00111
	STAP = 01000
	LDAP = 01001
	   . = 01010
	   . = 01011
	   . = 01100
	   . = 01101
	   . = 01110
	   . = 01111
	 AND = 10000
	 LDA = 10001
	 NOT = 10010
	 ADD = 10011
	   . = 10100
	   . = 10101
	   . = 10110
	   . = 10111
	 STA = 11000
	 JPC = 11001
	 JPZ = 11010
	 JP  = 11011
	 JSR = 11100
	 RTS = 11101
	 LXA = 11110
	HALT = 11111 (simulation only)
*/

module opccpu (

	input        reset_b,  // active low
	input        clk,
	output[10:0] address,
	output       rnw,
	inout[7:0]   data
);

	parameter FETCH0 = 0,
	          FETCH1 = 1,
	          RDMEM  = 2,
	          RDMEM2 = 3,
	          EXEC   = 4;

	parameter AND  = 5'bx0000,
	          LDA  = 5'bx0001,  // load accumulator
	          NOT  = 5'bx0010,
	          ADD  = 5'bx0011,
	          STAP = 5'b01000,
	          LDAP = 5'b01001,
	          STA  = 5'b11000,  // store accumulator
	          JPC  = 5'b11001,  // jump if carry
	          JPZ  = 5'b11010,  // jump if zero
	          JP   = 5'b11011,  // jump
	          JSR  = 5'b11100,  // jump to subroutine
	          RTS  = 5'b11101,  // return from subroutine
	          LXA  = 5'b11110;  // swap link and accumulator

	reg [10:0] OR_q,    // operand (...)
	           PC_q;    // program counter
	reg [7:0]  ACC_q;   // accumulator
	reg [4:0]  IR_q;    // instruction register / opcode
	reg [2:0]  FSM_q;   // finite state machine. Selects next microinstruction
	reg [2:0]  LINK_q;  // link register

	`define CARRY LINK_q[0]  // Bottom bit of link register doubles as carry flag

	wire writeback_w = ( ( FSM_q == EXEC ) &&
	                     ( IR_q == STA || IR_q == STAP )  // writeMem instruction
	                   ) & reset_b;

	assign rnw     = ~ writeback_w ;

	// if writeback, databus = accumulator else high impedance?
	assign data    = writeback_w ? ACC_q : 8'bz;
	// if writeback or readMem instr, address = operand else address = PC
	assign address = ( writeback_w || FSM_q == RDMEM || FSM_q == RDMEM2 ) ? OR_q : PC_q;

	// Microinstruction select
	always @ ( posedge clk or negedge reset_b )

		if ( ! reset_b )

			FSM_q <= FETCH0;

		else

			/*
			   FETCH0 -> FETCH1 -> EXEC
			                    -> RDMEM -> RDMEM2 -> EXEC
			                             -> EXEC
			*/

			case ( FSM_q )

				FETCH0 : FSM_q <= FETCH1;                            // get second byte
				FETCH1 : FSM_q <= ( IR_q[4] ) ? EXEC : RDMEM;        // if instruction has direct immediate,
				                                                     //  read Mem[ immediate ]
				RDMEM  : FSM_q <= ( IR_q == LDAP ) ? RDMEM2 : EXEC;  // if instruction has indirect immediate (pointer),
				                                                     //  read Mem[ Mem[ immediate ] ]
				RDMEM2 : FSM_q <= EXEC;
				EXEC   : FSM_q <= FETCH0;

			endcase

	// Fetch and Execute
	always @ ( posedge clk )
	begin

		IR_q       <= IR_q;        // default case
		OR_q[10:8] <= OR_q[10:8];  // default case

		/* OR_q[10:8] is upper part nybble for address.
		   Needs to be zeroed for both pointer READ and WRITE operations once ptr val is read
		*/
		if ( FSM_q == FETCH0 ) begin

			IR_q <= data[7:3];        // upper 5 bits of databus. Note, this is only place where instruction reg updated

			OR_q[10:8] <= data[2:0];  // lower 3 bits of databus

		end

		else if ( FSM_q == RDMEM )

			OR_q[10:8] <= 3'b000;

		OR_q[7:0] <= data;  // Always mirrors databus (t-1?). Whether value acted on depends on instruction
		                    // Lowest byte of OR is dont care in FETCH0 and at end of EXEC

		if ( FSM_q == EXEC )

			case ( IR_q )

				AND     : { `CARRY, ACC_q } <= {
				                                 1'b0,                      // carry = 0
				                                 ACC_q & OR_q[7:0]          // accumulator &= immediate
				                               };
				ADD     : { `CARRY, ACC_q } <= ACC_q + OR_q[7:0] + `CARRY;  // accumulator + immediate + carry

				NOT     : ACC_q             <= ~ OR_q[7:0];  // accumulator = ~ immediate
				LDA     : ACC_q             <=   OR_q[7:0];  // accumulator = immediate
				LDAP    : ACC_q             <=   OR_q[7:0];  // accumulator = immediate

				JSR     : { LINK_q, ACC_q } <= PC_q;         // upper 3 bits of PC are placed in link register,
				                                             //  lower 8 in accumulator

				LXA     : { LINK_q, ACC_q } <= {             // swap accumulator with link register
				                                 ACC_q[2:0], //  lower 3 bits of accumulator placed in link register
				                                 5'b00000,
				                                 LINK_q      //  link register placed in lower 3 bits of accumulator
				                               };

				default : { `CARRY, ACC_q } <= { `CARRY, ACC_q };

		  endcase
	end

	// Set program counter
	always @ ( posedge clk or negedge reset_b )

		// On reset start execution at 0x100 to leave page zero clear for variables
		if ( ! reset_b )

			PC_q <= 11'h100;

		// Increment program counter
		else if ( FSM_q == FETCH0 || FSM_q == FETCH1 )

			PC_q <= PC_q + 1;

		// Jump
		else

			case ( IR_q )

				JP      : PC_q <= OR_q;                         // unconditional jump to immediate
				JSR     : PC_q <= OR_q;                         // unconditional jump to immediate ... ??
				JPC     : PC_q <=    ( `CARRY ) ? OR_q : PC_q;  // jump if carry
				JPZ     : PC_q <= ~ ( | ACC_q ) ? OR_q : PC_q;  // jump if zero
				RTS     : PC_q <= {                             // jump to address stored in the registers
				                    LINK_q,
				                    ACC_q
				                  };

				default : PC_q <= PC_q;

			endcase
endmodule

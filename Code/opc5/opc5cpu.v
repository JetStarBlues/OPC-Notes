/*
	ppp l oooo ssss dddd  nnnnnnnnnnnnnnnn
	  \  \   \    \   \           \_______ 16b optional operand word
	   \  \   \    \   \__________________  4b reg2
	    \  \   \    \_____________________  4b reg1
	     \  \   \_________________________  4b opcode
	      \  \____________________________  1b instruction length
	       \______________________________  3b predicate bits


	16 entry register file
		. R0  - always zero
		. R15 - program counter

*/

/*
	Instructions
		LD  = x000
		ADD = x001
		AND = x010
		OR  = x011
		XOR = x100
		ROR = x101
		ADC = x110
		STO = x111

		Usage...
		LD   reg1 = EAD             reg1 = mem[EAD]
		ADD  reg1 += EAD            reg1 += mem[EAD]
		AND  reg1 &= EAD            reg1 &= mem[EAD]
		OR   reg1 |= EAD            reg1 |= mem[EAD]
		XOR  reg1 ^= EAD            reg1 ^= mem[EAD]
		ROR  reg1 = ROR( EAD, cIn)  reg1 = ROR( mem[EAD], cIn)  // ??
		ADC  reg1 += EAD + c        reg1 += mem[EAD] + c
		STO  mem[EAD] = reg1

		EAD = (reg2 + n) % 64   // ??

	Predicates
		110 - Always execute
		100 - Execute if zero flag set
		010 - Execute if carry flag set
		000 - Execute if both zero and carry flags set
		111 - Never execute... NOP
		101 - Execute if zero flag is clear
		011 - Execute if carry flag is clear
		001 - Execute if both zero and carry flags clear
*/
module opc5cpu (

	input        reset_b
	input        clk,
	input[15:0]  datain,
	output[15:0] dataout,
	output[15:0] address,
	output       rnw
);

	// JK ...
	`define i_predicate    15:13
	`define i_length       12
	`define i_opcode_indir 11
	`define i_opcode       10:8
	`define i_rSrc          7:4
	`define i_rDst          3:0
	`define i_operand      15:0


	(* RAM_STYLE="DISTRIBUTED" *)

	parameter FETCH0 = 0,
			  FETCH1 = 1,
			  EA_ED  = 2,  // ...
			  RDMEM  = 3,
			  EXEC   = 4,
			  WRMEM  = 5;

	parameter PRED_C      = 15,  // carry predicate  (bit15)
			  PRED_Z      = 14,  // zero predicate   (bit14)
			  PRED_INVERT = 13,  // invert predicate (bit13) ... action if flag set/clear
			  FSM_MAP0    = 12,  // ...
			  FSM_MAP1    = 11;  // ...

	parameter LD  = 3'b000,
			  ADD = 3'b001,
			  AND = 3'b010,
			  OR  = 3'b011,
			  XOR = 3'b100,
			  ROR = 3'b101,  // rotate right
			  ADC = 3'b110,
			  STO = 3'b111;  // store

	reg [15:0] OR_q,         // operand...
			   PC_q,         // program counter
			   IR_q,         // instruction register / opcode
			   result_q,     // result register (store ALU output)
			   result;       // (wire)
	reg [15:0] GRF_q[15:0];  // register file
	reg [3:0]  grf_adr_q;    // register file address
	reg [2:0]  FSM_q;        // finite state machine
	reg        C_q,          // carry register
			   zero,         // (wire)
			   carry;        // (wire)

	// For use once IR_q loaded ( FETCH1, EA_ED )
	wire predicate = IR_q[ PRED_INVERT ] ^ ( ( IR_q[ PRED_C ] | C_q  ) &
	                                         ( IR_q[ PRED_Z ] | zero )
	                                       );

	// For use before IR_q loaded ( FETCH0 )
	wire predicate_datain = datain[ PRED_INVERT ] ^ ( ( datain[ PRED_C ] | C_q  ) &
	                                                  ( datain[ PRED_Z ] | zero )
	                                                );

	wire [15:0] grf_dout;

	if ( grf_adr_q == 4'hF )  // this if-statement would be inside always @(*)

		// If R15, contents of program counter
		grf_dout = PC_q;

	else

		// If R0, zero. Else contents of register
		grf_dout = GRF_q[ grf_adr_q ] & { 16 { ( grf_adr_q != 4'h0 ) } };

	wire skip_eaed = ! ( ( grf_adr_q != 0           ) ||  // If is R0, or
	                     ( IR_q[ `i_opcode_indir ]  ) ||  //    is not indirect mode, or
	                     ( IR_q[ `i_opcode ] == STO )     //    is not STO
	                   );                                 // then skip EA_ED

	assign rnw = ! ( FSM_q == WRMEM );  // readMem

	assign dataout = grf_dout;  // dataout = register file output

	assign address = ( FSM_q == WRMEM || FSM_q == RDMEM ) ? OR_q : PC_q;


	// Arithmetic
	always @ ( * )  // combinatorial, no edge sensitive inputs
	begin

		// default values?
		result = 16'bx;
		carry  = C_q;
		zero   = ! ( | result_q );

		case ( IR_q[ `i_opcode ] )

			LD  : result = OR_q;
			ADD,
			ADC : { carry, result } = grf_dout + OR_q + ( ! IR_q[8] & C_q );  // IF ADC or ADD, IR_q[8] distinguishes between them
			AND : result            = ( grf_dout & OR_q );
			OR  : result            = ( grf_dout | OR_q );
			XOR : result            = ( grf_dout ^ OR_q );
			ROR : { result, carry } = {                      // ???
			                            carry,
			                            OR_q
			                          };

		endcase
	end

	// Microinstruction select
	always @ ( posedge clk or negedge reset_b )

		if ( ! reset_b )

			FSM_q <= FETCH0;

		else

			/*
				FETCH0 -> FETCH0
				       -> FETCH1 -> FETCH0
				                 -> EA_ED
				                 -> EXEC
				       -> EA_ED
	
				EA_ED -> FETCH0
				      -> EXEC
				      -> RDMEM -> EXEC
				      -> WRMEM -> FETCH0

				EXEC -> FETCH0
				     -> FETCH1
				     -> EA_ED
			*/

			case ( FSM_q )

				FETCH0 : begin

					if ( datain[ `i_length ] )      // get second word of instruction ??

						FSM_q <= FETCH1;

					else if ( ! predicate_datain )  // NOP

						FSM_q <= FETCH0;

					else                            // ...

						FSM_q <= EA_ED;
				end

				FETCH1 : begin

					if ( ! predicate )     // ...

						FSM_q <= FETCH0;

					else if ( skip_eaed )  // Allow FETCH1 to skip through to EXEC

						FSM_q <= EXEC;

					else                   // ...

						FSM_q <= EA_ED;     
				end

				EA_ED : begin

					if ( ! predicate )                   // ...

						FSM_q <= FETCH0;

					else if ( IR_q[ `i_opcode_indir ] )  // get indirect value

						FSM_q <= RDMEM;

					else if ( IR_q[ `i_opcode ] == STO )  // if STO, write memory

						FSM_q <= WRMEM;

					else                                  // ...

						FSM_q <= EXEC;
				end

				RDMEM : begin

					FSM_q <= EXEC;
				end

				EXEC : begin

					if ( IR_q[ `i_rDst ] == 4'hF )   // jump instruction, reset FSM state for next instruction

						FSM_q <= FETCH0;

					else if ( datain[ `i_length ] )  // get second word of instruction ??

						FSM_q <= FETCH1;

					else                             // ...

						FSM_q <= EA_ED;
				end

				default : begin

					FSM_q <= FETCH0;

				end

			endcase

	// Set address
	always @ ( posedge clk )

		case ( FSM_q )

			FETCH0,
			EXEC    : { grf_adr_q, OR_q } <= {
			                                   datain[ `i_rSrc ],
			                                   16'b0               // zero  ??
			                                 };
			FETCH1  : { grf_adr_q, OR_q } <= {
			                                   skip_eaed ? IR_q[ `i_rDst ] : IR_q[ `i_rSrc ],
			                                   datain              // if skip_eaed, mem[ r2 ], else mem[ r1 ]  ??
			                                 };
			RDMEM   : { grf_adr_q, OR_q } <= {
			                                   IR_q[ `i_rDst ],
			                                   datain              // mem[ r2 ]  ??
			                                 };
			EA_ED   : { grf_adr_q, OR_q } <= {
			                                   IR_q[ `i_rDst ],
			                                   grf_dout + OR_q     // r2 + n  ??
			                                 };
			default : { grf_adr_q, OR_q } <= {
			                                     4'bx,
			                                    16'bx
			                                  };

		endcase

	// Set program counter
	always @ ( posedge clk or negedge reset_b )

		if ( ! reset_b )

			PC_q <= 16'b0000000000000000;

		else if ( FSM_q == FETCH0 || FSM_q == FETCH1 )

			PC_q <= PC_q + 1;

		else if ( FSM_q == EXEC )

			if ( grf_adr_q == 4'hF )

				PC_q <= result;  // jump

			else

				PC_q <= PC_q + 1;

		// else PC doesn't change

	// ??
	always @ ( posedge clk )

		if ( FSM_q == FETCH0 )

			IR_q <= datain;

		else if ( FSM_q == EXEC )

			C_q                <= carry;
			GRF_q[ grf_adr_q ] <= result;
			result_q           <= result;
			IR_q               <= datain;

endmodule

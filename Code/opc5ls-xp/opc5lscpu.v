/*
  XP differences:
  - dual read port??
      -> dst and src registers can be read in same cycle
      -> no need for regFileAddress register
  - FETCH0, EXEC
      -> option to go directly to EXEC
*/

module opc5lscpu (

	input        reset_b,
	input        clk,
	input        clken,
	input[15:0]  din,
	input        int_b,
	output[15:0] dout,
	output[15:0] address,
	output       rnw,
	output       vpa,  // program memory?
	output       vda   // data memory?
);

	// JK ...
	`define i_predicate 15:13
	`define i_length    12
	`define i_opcode    11:8
	`define i_rSrc       7:4
	`define i_rDst       3:0
	`define i_operand   15:0

	parameter MOV  = 4'h0,
	          AND  = 4'h1,
	          OR   = 4'h2,
	          XOR  = 4'h3,
	          ADD  = 4'h4,
	          ADC  = 4'h5,
	          STO  = 4'h6,
	          LD   = 4'h7,
	          ROR  = 4'h8,
	          NOT  = 4'h9,
	          SUB  = 4'hA,
	          SBC  = 4'hB,
	          CMP  = 4'hC,
	          CMPC = 4'hD,
	          BSWP = 4'hE,
	          PSR  = 4'hF;

	parameter FETCH0 = 3'h0,
	          FETCH1 = 3'h1,
	          EA_ED  = 3'h2,
	          RDMEM  = 3'h3,
	          EXEC   = 3'h4,
	          WRMEM  = 3'h5,
	          INT    = 3'h6;

	parameter EI         = 3,         // PSR enable hardware interrupts
	          S          = 2,         // PSR sign
	          C          = 1,         // PSR carry
	          Z          = 0,         // PSR zero
	
	          P0          = 15,
	          P1          = 14,
	          P2          = 13,
	          IRLEN       = 12,
	          IR_LD       = 16,        // is LD
	          IR_STO      = 17,        // is STO
	          IR_GETPSR   = 18,        // is get_psr
	          IR_SETPSR   = 19,        // is set_psr
	          IR_RTI      = 20,        // is RTI
	          IR_CMP      = 21,        // is CMP/CMPC

	          INT_VECTOR = 16'h0002;

	(* RAM_STYLE="DISTRIBUTED" *)

	reg [21:0] IR_q;          // instruction register
	reg [15:0] OR_q,          // operand register
	           PC_q,          // program counter
	           PCI_q,         // backup, state at intAck ??
	           result;        // (wire) ALU_out
	reg [15:0] dprf_q[15:0];  // register file (dual port)
	reg [7:0]  PSR_q;         // program status register
	reg [3:0]  swiid,         // (wire) software interrupt
	           PSRI_q;        // backup, state at intAck ??
	reg [2:0]  FSM_q;         // finite state machine
	reg        zero,          // (wire)
	           carry,         // (wire)
	           sign,          // (wire)
	           enable_int,    // (wire)
	           reset_s0_b,    //
	           reset_s1_b;    //

	wire predicate;
	wire p_;

	if ( IR_q[ P1 ] )  // this if-statement would be inside always @(*)

		if ( IR_q[ P0 ] )

			p_ = PSR_q[ S ];      // conditional to sign flag

		else

			p_ = PSR_q[ Z ];      // conditional to zero flag

	else if ( IR_q[ P0 ] )

		p_ = PSR_q[ C ];          // conditional to carry flag

	else

		p_ = 1;                   // always execute or NOP

	predicate = IR_q[ P2 ] ^ p_;  // P2 determines if execute when flag set or clear


	wire predicate_din = din[ P2 ] ^ ( din[ P1 ] ? ( din[ P0 ] ? PSR_q[ S ] : PSR_q[ Z ] ) : ( din[ P0 ] ? PSR_q[ C ] : 1 ) );


	// Port 1 always reads dest reg
	wire [15:0] dprf_dout;

	if ( IR_q[ `i_rDst ] == 4'hF )  // this if-statement would be inside always @(*)

		dprf_dout = PC_q;

	else

		dprf_dout = dprf_q[ IR_q[ `i_rDst ] ] & { 16 { IR_q[ `i_rDst ] != 4'h0 } };  // regFile contents. If r0, zero

	// Port 2 always reads source reg
	wire [15:0] dprf_dout_p2;

	if ( IR_q[ `i_rSrc ] == 4'hF )  // this if-statement would be inside always @(*)

		dprf_dout_p2 = PC_q;

	else

		dprf_dout_p2 = dprf_q[ IR_q[ `i_rSrc ] ] & { 16 { IR_q[ `i_rSrc ] != 4'h0 } };  // regFile contents. If r0, zero


	wire [15:0] operand = ( IR_q[ IRLEN ] || IR_q[ IR_LD ] ) ? OR_q : dprf_dout_p2;  // ?? ... For one word instructions operand comes from dprf

	assign dout    =  dprf_dout;
	assign address =  ( FSM_q == WRMEM || FSM_q == RDMEM ) ? OR_q : PC_q;

	assign rnw     =  ! ( FSM_q == WRMEM );

	assign vpa = ( FSM_q == FETCH0 ) || ( FSM_q == FETCH1 ) || ( FSM_q == EXEC );  // accesses program memory
	assign vda = ( FSM_q == RDMEM ) || ( FSM_q == WRMEM );                         // accesses data memory


	always @ ( * )
	begin

		// no real need for LD? and STO entries? but include it so all instructions are covered and no need for default
		case ( IR_q[ `i_opcode ] )

			LD, STO,  // ...
			MOV,PSR          : { carry, result } = {
			                                         PSR_q[ C ],
			                                         ( IR_q[ IR_GETPSR ] ) ? { 8'b0, PSR_q } :  // PSR
			                                                                 operand            // ED
			                                       };

			AND,OR           : { carry, result } = {
			                                         PSR_q[ C ],
			                                         ( IR_q[ 8 ] ) ? ( dprf_dout & operand ) :
			                                                         ( dprf_dout | operand )
			                                       };

			ADD,ADC          : { carry, result } = dprf_dout + operand + ( IR_q[ 8 ] & PSR_q[ C ] );

			SUB,SBC,CMP,CMPC : { carry, result } = dprf_dout +
			                                       ( operand ^ 16'hFFFF ) +  // two's complement
			                                       ( IR_q[ 8 ] ? PSR_q[ C ] : 1 );

			XOR,BSWP         : { carry, result } = {
			                                         PSR_q[ C ],
			                                         ( ! IR_q[ 11 ] ) ? ( dprf_dout ^ operand ) :
			                                                            {
			                                                              operand[7:0],
			                                                              operand[15:8]  // byte swap
			                                                            }
			                                       };

			NOT,ROR          : { result, carry } = ( IR_q[ 8 ] ) ? {
			                                                         ~ operand,
			                                                         PSR_q[ C ]
			                                                       } :
			                                                       {
			                                                         PSR_q[ C ],
			                                                         operand
			                                                       };

		endcase

		// Status bits
		if ( IR_q[ IR_SETPSR ] )

			{ swiid, enable_int, sign, carry, zero } = operand[7:0];

		else if ( IR_q[ `i_rDst ] != 4'hF )  // rDst != PC  ??

			{
			  swiid,
			  enable_int,
			  sign,
			  carry,
			  zero
			} = {
		          PSR_q[7:3],     // swiid, enable_int (old values)
		          result[15],     // sign
		          carry,          // carry
		          ! ( | result )  // zero
		        };

		else  // ??

			{ swiid, enable_int, sign, carry, zero } = PSR_q;

	end


	always @ ( posedge clk )

		if ( clken ) begin

			// metastability?
			reset_s0_b <= reset_b;
			reset_s1_b <= reset_s0_b;

			if ( ! reset_s1_b ) begin

				PC_q   <= 0;
				PCI_q  <= 0;
				PSRI_q <= 0;
				PSR_q  <= 0;
				FSM_q  <= 0;

			end

			else begin

				case ( FSM_q )

					FETCH0 : begin

						if ( din[ `i_length ] )

							FSM_q <= FETCH1;

						else if ( ! predicate_din )  // if NOP

							FSM_q <= FETCH0;

						else if ( ( din[ `i_opcode ] == LD ) || ( din[ `i_opcode ] == STO ) )  // if memory access

							FSM_q <= EA_ED;

						else

							FSM_q <= EXEC;

					end

					FETCH1 : begin

						if ( ! predicate )                          // if NOP

							FSM_q <= FETCH0;

						else if ( ( sprf_radr_q != 0 ) ||           // if not RO or is LD/STO
							      IR_q[ IR_LD ] || IR_q[ IR_STO ]
						        )

							FSM_q <= EA_ED;

						else

							FSM_q <= EXEC;
					end

					EA_ED : begin

						if ( ! predicate )

							FSM_q <= FETCH0;

						else if ( IR_q[ IR_LD ] )

							FSM_q <= RDMEM;

						else if ( IR_q[ IR_STO ] )

							FSM_q <= WRMEM;

						else

							FSM_q <= EXEC;
					end

					RDMEM : begin

						FSM_q <= EXEC;

					end

					WRMEM : begin

						if ( ! int_b & PSR_q[ EI ] )  // interrupt and interrupts enabled

							FSM_q <= INT;

						else

							FSM_q <= FETCH0;

					end

					EXEC : begin

						if ( ( ! int_b & PSR_q[ EI ] )            ||  // hardware interrupt
							 ( IR_q[ IR_SETPSR ] && ( | swiid ) )     // software interrupt
						   )

							FSM_q <= INT;

						// go to fetch0 if PC or PSR? affected by exec
						else if ( IR_q[ `i_rDst ] == 4'hF )  // rti

							FSM_q <= FETCH0;

						// ...
						else if ( din[ `i_length ] )

							FSM_q <= FETCH1;

						// load/store have to go via EA_ED
						else if ( ( din[ `i_opcode ] == LD) || ( din[ `i_opcode ] == STO ) )  // memory access

							FSM_q <= EA_ED;

						// shortcut to exec on all predicates
						else if ( din[P2] ^ (din[P1] ? ( din[P0] ? sign : zero ): ( din[P0] ? carry : 1 ) ) )  // is not NOP
							                                                                                   //  predicate_din using zero/carry/sign wires instead of reg values

							FSM_q <= EXEC;

						else

							FSM_q <= FETCH0;

						// or short cut on always only
						/*else if ( din[ 15:13 ] == 3'b000 )

							FSM_q <= EXEC;

						else

							FSM_q <= EA_ED;
						*/

					end

					default : begin

						FSM_q <= FETCH0;

					end

				endcase // case (FSM_q)


				// Operand...
				if ( FSM_q == FETCH0 || FSM_q == EXEC )

					OR_q <= 16'b0;

				else if ( FSM_q == EA_ED )

					OR_q <= dprf_dout_p2 + OR_q;

				else

					OR_q <= din;


				// Program counter
				if ( FSM_q == INT )

					PC_q        <= INT_VECTOR;  // jump to interrupt handler
					PCI_q       <= PC_q;        // save program counter
					PSRI_q      <= PSR_q[3:0];  // save status register
					PSR_q[ EI ] <= 1'b0;        // Always clear EI on taking interrupt


				else if ( FSM_q == FETCH0 || FSM_q == FETCH1 )

					PC_q <= PC_q + 1;


				else if ( FSM_q == EXEC )
				begin

					// PC_q
					if ( IR_q[ IR_RTI ] )                           // restore program counter

						PC_q <= PCI_q;

					else if ( IR_q[ `i_rDst ] == 4'hF )             // set program counter (jump)

						PC_q <= result;

					else if ( ( ! int_b && PSR_q[ EI ] ) ||         // hardware interrupt and interrupts enabled
					          ( IR_q[ IR_SETPSR ] && ( | swiid ) )  // software interrupt (setPSR instruction that sets swiid bits 1..15)
					        )

						PC_q <= PC_q;

					else                                            // increment

						PC_q <= PC_q + 1;


					// PSR_q
					if ( IR_q[ IR_RTI ] )  // restore status register

						PSR_q <= {
					               4'b0,   // clear SWI bits on return
					               PSRI_q
					             };

					else                   // default...

						PSR_q <= { swiid, enable_int, sign, carry, zero };


					// regFile_q
					if ( ! IR_q[ IR_CMP ] )

						dprf_q[ IR_q[ `i_rDst ] ] <= result;  // if not CMP/CMPC write to rDst

				end


				// Set instruction register including extra bits [21:16]
				if ( FSM_q == FETCH0 || FSM_q == EXEC )

					IR_q <= {

						// IR_CMP (21)
						( ( din[ `i_opcode ] == CMP ) || ( din[ `i_opcode ] == CMPC ) ),

						{
							3 { ( din[ `i_opcode ] == PSR ) }
						}
						&
						{
							( din[ `i_rDst ] == 4'hF ),  // IR_RTI    (20),  assembly -> rti  pc, pc
							( din[ `i_rDst ] == 4'h0 ),  // IR_SETPSR (19),  assembly -> psr psr, rs
							( din[ `i_rSrc ] == 4'h0 )   // IR_GETPSR (18),  assembly -> psr  rd, psr
						},

						// IR_STO (17)
						( din[ `i_opcode ] == STO ),

						// IR_LD (16)
						( din[ `i_opcode ] == LD ),

						// (15..0)
						din
					};

			end
		end

endmodule

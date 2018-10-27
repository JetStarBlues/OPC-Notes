/*
	ppp l oooo ssss dddd  nnnnnnnnnnnnnnnn
	  \  \   \    \   \           \_______ 16b optional operand word
	   \  \   \    \___\__________________  4b source and destination registers
	    \  \___\__________________________  1b instruction length + 4b opcode
	     \________________________________  3b predicate bits   


	P0  P1  P2  Asm Prefix  Function
	--  --  --  ----------  --------
	0   0   0   1. or none  Always execute
	0   0   1   0.          Never execute - NOP
	0   1   0   z.          Execute if Zero flag is set
	0   1   1   nz.         Execute if Zero flag is clear
	1   0   0   c.          Execute if Carry flag is set
	1   0   1   nc.         Execute if Carry flag is clear
	1   1   0   mi.         Execute if Sign flag is set
	1   1   1   pl.         Execute if Sign flag is clear


	Suffixes
	--------
		none - one byte instruction                 (rd, rs)
		.i   - has immediate (two byte instruction) (rd, rs, imm)


	Addressing modes...
	-------------------

		???    ???            EA/ED
		----   -----------    ---------------
		....   rY, rX, 0      mem[ rX + 0   ]
		....   rY, rX, imm    mem[ rX + imm ]
		....   rY, r0, imm    mem[  0 + imm ]
		....   rY, r0, imm    imm                ???


	PSR
	---
	7 - SWI3
	6 - SWI2
	5 - SWI1
	4 - SWI0
	3 - EI
	2 - S
	1 - C
	0 - Z


	#    opcode    mnemonic   alias         FUNCTION                                Assembler      EA/ED Calc         Assembler              EA/ED Calc              
	--   -------   --------   -----------   -------------------------------------   ------------   ----------------   --------------------   ------------------------
	0    0 0 0 0   mov                      rd                 <- ED                mov   rd, rs   ED = rs + 0        mov   rd,  rs, imm     ED = rs + imm & 0xFFFF
	1    0 0 0 1   and                      rd                 <- rd & ED           and   rd, rs   ED = rs + 0        and   rd,  rs, imm     ED = rs + imm & 0xFFFF
	2    0 0 1 0   or                       rd                 <- rd | ED           or    rd, rs   ED = rs + 0        or    rd,  rs, imm     ED = rs + imm & 0xFFFF
	3    0 0 1 1   xor                      rd                 <- rd ^ ED           xor   rd, rs   ED = rs + 0        xor   rd,  rs, imm     ED = rs + imm & 0xFFFF
	4    0 1 0 0   add         asl rd, rd   {C, rd}            <- rd + ED           add   rd, rs   ED = rs + 0        add   rd,  rs, imm     ED = rs + imm & 0xFFFF
	5    0 1 0 1   adc         rol rd, rd   {C, rd}            <- rd + ED + C       adc   rd, rs   ED = rs + 0        adc   rd,  rs, imm     ED = rs + imm & 0xFFFF
	6    0 1 1 0   sto                      mem[EA]            <- rd                sto   rd, rs   EA = rs + 0        sto   rd,  rs, imm     EA = rs + imm & 0xFFFF
	7    0 1 1 1   ld                       rd                 <- mem[EA]           ld    rd, rs   EA = rs + 0        ld    rd,  rs, imm     EA = rs + imm & 0xFFFF
	8    1 0 0 0   ror                      {rd, C}            <- {C, ED}           ror   rd, rs   ED = rs + 0        sub   rd,  rs, imm     ED = rs + imm & 0xFFFF
	9    1 0 0 1   not                      rd                 <- ~ED               not   rd, rs   ED = rs + 0        not   rd,  rs, imm     ED = rs + imm & 0xFFFF
	10   1 0 1 0   sub                      {C, rd}            <- rd + ~ED + 1      sub   rd, rs   ED = rs + 0        sub   rd,  rs, imm     ED = rs + imm & 0xFFFF
	11   1 0 1 1   sbc                      {C, rd}            <- rd + ~ED + C      sbc   rd, rs   ED = rs + 0        sbc   rd,  rs, imm     ED = rs + imm & 0xFFFF
	12   1 1 0 0   cmp                      {C, r0}            <- rd + ~ED + 1      cmp   rd, rs   ED = rs + 0        cmp   rd,  rs, imm     ED = rs + imm & 0xFFFF
	13   1 1 0 1   cmpc                     {C, r0}            <- rd + ~ED + C      cmpc  rd, rs   ED = rs + 0        cmpc  rd,  rs, imm     ED = rs + imm & 0xFFFF
	14   1 1 1 0   bswp                     {rd_h, rd_l}       <- {ED_l, ED_h}      bswp  rd, rs   ED = rs + 0        bswp  rd,  rs, imm     ED = rs + imm & 0xFFFF
	15   1 1 1 1   psr                      rd                 <- ED                psr   rd, psr  ED = {8’b0, PSR}   psr   rd, psr, imm     ED = {8’b0,PSR}         
	15   1 1 1 1   psr                      {SWI, EI, S, C, Z} <- ED[7:0]           psr  psr, rs   ED = rs + 0        psr  psr,  rs, imm     ED = rs + imm & 0xFFFF
	15   1 1 1 1   rti                      {EI, S, C, Z}      <- {0, S’, C’, Z’}   rti   pc, pc   ED = pc’           -                      -                       

    Interrupt SWI bits
    0     - NA used as check (hardware interrupt via int_b)
    1..15 - software interrupt n
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
	reg [15:0] sprf_q[15:0];  // register file
	reg [7:0]  PSR_q;         // program status register
	reg [3:0]  sprf_radr_q,   // register file address
	           swiid,         // (wire) software interrupt
	           PSRI_q;        // backup, state at intAck ??
	reg [2:0]  FSM_q;         // finite state machine
	reg        zero,          // (wire)
	           carry,         // (wire)
	           sign,          // (wire)
	           enable_int,    // (wire)
	           reset_s0_b,    // (wire) metastability flipflops
	           reset_s1_b;    // (wire) metastability flipflops

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


	wire [15:0] sprf_dout;

	if ( sprf_radr_q == 4'hF )  // this if-statement would be inside always @(*)

		sprf_dout = PC_q;

	else

		sprf_dout = sprf_q[ sprf_radr_q ] & { 16 { sprf_radr_q != 4'h0 } };  // regFile contents. If r0, zero


	assign dout    =  sprf_dout;
	assign address =  ( FSM_q == WRMEM || FSM_q == RDMEM ) ? OR_q : PC_q;

	assign rnw     =  ! ( FSM_q == WRMEM );

	assign vpa = ( FSM_q == FETCH0 ) || ( FSM_q == FETCH1 ) || ( FSM_q == EXEC );  // accesses program memory
	assign vda = ( FSM_q == RDMEM ) || ( FSM_q == WRMEM );                         // accesses data memory


	always @ ( * )
	begin

		// Arithmetic
		if ( FSM_q == EA_ED )

			// EAD for all instructions is created by adding the 16b operand to the source register
			//  carry is dont care in this state
			{ carry, result } = sprf_dout + OR_q;

		else

			// no real need for LD? and STO entries? but include it so all instructions are covered and no need for default
			case ( IR_q[ `i_opcode ] )

				LD, STO,  // ...
				MOV,PSR          : { carry, result } = {
				                                         PSR_q[ C ],
				                                         ( IR_q[ IR_GETPSR ] ) ? { 8'b0, PSR_q } :  // PSR
				                                                                 OR_q                // ED
				                                       };

				AND,OR           : { carry, result } = {
				                                         PSR_q[ C ],
				                                         ( IR_q[ 8 ] ) ? ( sprf_dout & OR_q ) :
				                                                         ( sprf_dout | OR_q )
				                                       };

				ADD,ADC          : { carry, result } = sprf_dout + OR_q + ( IR_q[ 8 ] & PSR_q[ C ] );

				SUB,SBC,CMP,CMPC : { carry, result } = sprf_dout +
				                                       ( OR_q ^ 16'hFFFF ) +  // two's complement
				                                       ( IR_q[ 8 ] ? PSR_q[ C ] : 1 );

				XOR,BSWP         : { carry, result } = {
				                                         PSR_q[ C ],
				                                         ( ! IR_q[ 11 ] ) ? ( sprf_dout ^ OR_q ) :
				                                                            {
				                                                              OR_q[7:0],
				                                                              OR_q[15:8]  // byte swap
				                                                            }
				                                       };

				NOT,ROR          : { result, carry } = ( IR_q[ 8 ] ) ? {
				                                                         ~ OR_q,
				                                                         PSR_q[ C ]
				                                                       } :
				                                                       {
				                                                         PSR_q[ C ],
				                                                         OR_q
				                                                       };

			endcase

		// Status bits
		if ( IR_q[ IR_SETPSR ] )

			{ swiid, enable_int, sign, carry, zero } = OR_q[7:0];  // ...

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
	begin

		if ( clken ) begin

			// metastability?
			reset_s0_b <= reset_b;
			reset_s1_b <= reset_s0_b;

			if ( ! reset_s1_b )

				PC_q   <= 0;
				PCI_q  <= 0;
				PSRI_q <= 0;
				PSR_q  <= 0;
				FSM_q  <= 0;

			else begin

				/*
					FETCH0 -> FETCH0
					       -> FETCH1 -> FETCH0
					                 -> EA_ED
					                 -> EXEC
					       -> EA_ED

			        EA_ED  -> FETCH0
					       -> EXEC
					       -> RDMEM  -> EXEC
					       -> WRMEM  -> INT
					                 -> FETCH0

					EXEC -> INT
					     -> FETCH0
					     -> FETCH1
					     -> EA_ED
				*/
				case ( FSM_q )

					FETCH0 : begin

						if ( din[ `i_length ] )      // ??

							FSM_q <= FETCH1;

						else if ( ! predicate_din )  // if NOP

							FSM_q <= FETCH0;

						else

							FSM_q <= EA_ED;
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

						else if ( IR_q[ `i_rDst ] == 4'hF )  // rti

							FSM_q <= FETCH0;

						else if ( din[ `i_length ] )

							FSM_q <= FETCH1;

						else

							FSM_q <= EA_ED;

					end

					default : begin

						FSM_q <= FETCH0;

					end

				endcase


				// Address, operand
				case ( FSM_q )

					FETCH0, EXEC : { sprf_radr_q, OR_q } <= {
					                                          din[ `i_rSrc ],
					                                          16'b0
					                                        };
					FETCH1 : begin

						if ( ( sprf_radr_q != 0 ) ||
						     IR_q[ IR_LD ] || IR_q[ IR_STO ] 
						   )

							sprf_radr_q <= IR_q[ `i_rSrc ];

						else

							sprf_radr_q <= IR_q[ `i_rDst ];

						OR_q <= din;

					end

					EA_ED   : { sprf_radr_q, OR_q } <= {
					                                     IR_q[ `i_rDst ],
					                                     result            // use ALU to compute effective address/data
					                                   };

					default : { sprf_radr_q, OR_q } <= {
					                                     IR_q[ `i_rDst ],
					                                     din
					                                   };

				endcase


				// Program counter, PSR_q, sprf_q
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
					sprf_q[
					        IR_q[ IR_CMP ] ? 4'b0 : IR_q[ `i_rDst ]  // if CMP/CMPC write to R0, else to RDst
					      ] <= result;

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
	end

endmodule

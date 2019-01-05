
/*
	ppp l oooo ssss dddd  nnnnnnnnnnnnnnnn
	  \  \   \    \   \           \_______ 16b optional operand word
	   \  \   \    \___\__________________  4b source and destination registers
	    \  \___\__________________________  1b instruction length + 4b opcode
	     \________________________________  3b predicate bits


	P0  P1  P2  Asm Prefix  Function
	--  --  --  ----------  --------
	0   0   0   1. or none  Always execute
	0   0   1   0.          Used as 5th opcode bit for extended instructions
	0   1   0   z.          Execute if Zero flag is set
	0   1   1   nz.         Execute if Zero flag is clear
	1   0   0   c.          Execute if Carry flag is set
	1   0   1   nc.         Execute if Carry flag is clear
	1   1   0   mi.         Execute if Sign flag is set
	1   1   1   pl.         Execute if Sign flag is clear

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

	#    opcode    mnemonic   description                       FUNCTION                                Assembler         EA/ED Calc           Assembler              EA/ED Calc              
	--   -------   --------   ------------------------------    -----------------------------------     --------------    ------------------   --------------------   --------------
	 0   00000     mov        register move                     rd                 <- ED                mov     rd, rs    ED = rs + 0          mov     rd,  rs, imm   ED = rs + imm
	 1   00001     and        logical and                       rd                 <- rd & ED           and     rd, rs    ED = rs + 0          and     rd,  rs, imm   ED = rs + imm
	 2   00010     or         logical or                        rd                 <- rd | ED           or      rd, rs    ED = rs + 0          or      rd,  rs, imm   ED = rs + imm
	 3   00011     xor        logical xor                       rd                 <- rd ^ ED           xor     rd, rs    ED = rs + 0          xor     rd,  rs, imm   ED = rs + imm
	 4   00100     add                                          {C, rd}            <- rd + ED           add     rd, rs    ED = rs + 0          add     rd,  rs, imm   ED = rs + imm
	 5   00101     adc        add with carry                    {C, rd}            <- rd + ED + C       adc     rd, rs    ED = rs + 0          adc     rd,  rs, imm   ED = rs + imm
	 6   00110     sto        write memory                      mem[EA]            <- rd                sto     rd, rs    EA = rs + 0          sto     rd,  rs, imm   EA = rs + imm
	 7   00111     ld         read memory                       rd                 <- mem[EA]           ld      rd, rs    EA = rs + 0          ld      rd,  rs, imm   EA = rs + imm
	 8   01000     ror        rotate right through carry        {rd, C}            <- {C, ED}           ror     rd, rs    ED = rs + 0          sub     rd,  rs, imm   ED = rs + imm
	 9   01001     jsr        jump to subroutine                rd                 <- PC;
	                                                            PC                 <- EA                jsr     rd, rs    EA = rs + 0          jsr     rd,  rs, imm   EA = rs + imm
	10   01010     sub                                          {C, rd}            <- rd + ~ED + 1      sub     rd, rs    ED = rs + 0          sub     rd,  rs, imm   ED = rs + imm
	11   01011     sbc        subtract with carry               {C, rd}            <- rd + ~ED + C      sbc     rd, rs    ED = rs + 0          sbc     rd,  rs, imm   ED = rs + imm
	12   01100     inc        increment                         {C, rd}            <- rd + ED           inc     rd, imm   ED = r0 + <4b imm>
	13   01101     lsr        logical shift right               {rd, C}            <- {0, ED}           lsr     rd, rs    ED = rs + 0          lsr     rd,  rs, imm   ED = rs + imm
	14   01110     dec        decrement                         {C, rd}            <- rd + ~ED + 1      dec     rd, imm   ED = r0 + <4b imm>
	15   01111     asr        arithmetic shift right            {rd, C}            <- {ED[15], ED}      asr     rd, rs    ED = rs + 0          asr     rd,  rs, imm   ED = rs + imm

	16   10000     halt                                         rd                 <- ED                halt    rd, rs    ED = rs + 0          halt    rd,  rs, imm   ED = rs + imm
	17   10001     bswp       byte swap                         {rd_h, rd_l}       <- {ED_l, ED_h}      bswp    rd, rs    ED = rs + 0          bswp    rd,  rs, imm   ED = rs + imm
	18   10010     setpsr                                       psr                <- ED                setpsr psr, rs    ED = rs + 0          setpsr psr,  rs, imm   ED = rs + imm
	19   10011     getpsr                                       rd                 <- ED                getpsr  rd, psr   ED = psr + 0         getpsr  rd, psr, imm   ED = psr + imm
	20   10100     rti        return from interrupt             rd                 <- EA                rti     pc, pc    EA = shadow PC
	21   10101     not                                          rd                 <- ~ED               not     rd, rs    ED = rs + 0          not     rd,  rs, imm   ED = rs + imm
	22   10110     out        IO output                         IO[EA]             <- rd                out     rd, rs    EA = rs + 0          out     rd,  rs, imm   EA = rs + imm
	23   10111     in         IO input                          rd                 <- IO[EA]            in      rd, rs    EA = rs + 0          in      rd,  rs, imm   EA = rs + imm
	24   11000     push       memory store with pre-indexing    mem[EA]            <- rd;
                                                                rs                 <- EA                push    rd, rs    EA = rs - 1          push    rd,  rs, imm   EA = rs + imm
	25   11001     pop        memory read with post-indexing    rd                 <- mem[rs];
                                                                rs                 <- EA                pop     rd, rs    EA = rs + 1          pop     rd,  rs, imm   EA = rs + imm
	26   11010     cmp        compare                           {C, r0}            <- rd + ~ED + 1      cmp     rd, rs    ED = rs + 0          cmp     rd,  rs, imm   ED = rs + imm
	27   11011     cmpc       compare with carry                {C, r0}            <- rd + ~ED + C      cmpc    rd, rs    ED = rs + 0          cmpc    rd,  rs, imm   ED = rs + imm


	Instructions 16..27 always execute (no predication)

*/

module opc6cpu (

	input        reset_b,
	input        clk,
	input        clken,
	input [15:0] din,
	input [1:0]  int_b,    // two interrupt pins

	output [15:0] dout,
	output [15:0] address,
	output        rnw,
	output        vpa,     // program memory access
	output        vda,     // data memory access
	output        vio      // IO access
);

	// JK ...
	`define i_predicate 15:13
	`define i_length    12
	`define i_opcode    11:8
	`define i_rSrc       7:4
	`define i_rDst       3:0
	`define i_operand   15:0

	parameter MOV    = 5'h0,
	          AND    = 5'h1,
	          OR     = 5'h2,
	          XOR    = 5'h3,
	          ADD    = 5'h4,
	          ADC    = 5'h5,
	          STO    = 5'h6,
	          LD     = 5'h7,
	          ROR    = 5'h8,
	          JSR    = 5'h9,
	          SUB    = 5'hA,
	          SBC    = 5'hB,
	          INC    = 5'hC,
	          LSR    = 5'hD,
	          DEC    = 5'hE,
	          ASR    = 5'hF,
	          HLT    = 5'h10,
	          BSWP   = 5'h11,
	          SETPSR = 5'h12,
	          GETPSR = 5'h13,
	          RTI    = 5'h14,
	          NOT    = 5'h15,
	          OUT    = 5'h16,
	          IN     = 5'h17,
	          PUSH   = 5'h18,
	          POP    = 5'h19,
	          CMP    = 5'h1A,
	          CMPC   = 5'h1B;

	parameter FETCH0 = 3'h0,
	          FETCH1 = 3'h1,
	          EAD    = 3'h2,
	          RDMEM  = 3'h3,
	          EXEC   = 3'h4,
	          WRMEM  = 3'h5,
	          INT    = 3'h6;

	parameter EI          = 3,   // status flag - used to enable or disable hardware interrupts
	          S           = 2,   // status flag - sign, set when MSB of result is '1'
	          C           = 1,   // status flag - carry, set or cleared only on arithmetic operations
	          Z           = 0,   // status flag - zero, set on every instruction based on state of destination register

	          P0          = 15,
	          P1          = 14,
	          P2          = 13,
	          IRLEN       = 12,
	          IR_LD       = 16,
	          IR_STO      = 17,
	          IR_NOPRED   = 18,  // no predicate, ops 16..27
	          IR_WBK      = 19,  // ??

	          INT_VECTOR0 = 16'h0002,  // jump address if int_b[0] or SWI (ISR is reponsible for checking SWI bits to determine if software or hardware interrupt)
	          INT_VECTOR1 = 16'h0004;  // jump address if int_b[1] (priority over int_b[0])

	(* RAM_STYLE = "DISTRIBUTED" *)

	reg [19:0] IR_q;        // instruction register
	reg [15:0] OR_q,        // operand register
	           PC_q,        // program counter
	           PCI_q,       // backup, state at intAck ??
	           result;      // (wire) ALU_out
	reg [15:0] RF_q[15:0];  // register file (dual read port)
	reg [7:0]  PSR_q;       // program status register
	reg [3:0]  swiid,       // (wire) software interrupt
	           PSRI_q;      // backup, state at intAck ??
	reg [2:0]  FSM_q;       // finite state machine
	reg        zero,        // (wire)
	           carry,       // (wire)
	           sign,        // (wire)
	           enable_int,  // (wire)
	           reset_s0_b,  // (wire) 
	           reset_s1_b,  // (wire)
	           pred_q;      // ??

	wire [4:0] op = {     // delayed 1 cycle?

		IR_q[ IR_NOPRED ],
		IR_q[ `i_opcode ]
	};

	wire [4:0]  op_d = {  // immediate ?

		( din[ `i_predicate ] == 3'b001 ),  // predicate bit used as 5th opcode bit
		din[ `i_opcode ]
	};

	// New data, new flags (in exec/fetch)
	wire pred_d;
	wire p_;
	wire pp_;

	if ( din[ P1 ] )  // this if-statement would be inside always @(*)

		if ( din[ P0 ] )

			p_ = sign;       // conditional to sign flag

		else

			p_ = zero;       // conditional to zero flag

	else if ( din[ P0 ] )

		p_ = carry;          // conditional to carry flag

	else

		p_ = 1;              // always execute or NOP

	pp_ = din[ P2 ] ^ p_;  // P2 determines if execute when flag set or clear

	pred_d = ( din[ `i_predicate ] == 3'b001 ) || pp_;  // 001 is not used as predicate, instead extra opcode bit for instructions 16..27 (1xxxx)
	                                                    //  As such instructions 16..27 always execute (not conditional)

	// New data, old flags (in fetch0)
	wire pred_din = ( din[ `i_predicate ] == 3'b001 ) || 
	                ( din[ P2 ] ^ ( din[ P1 ] ? ( din[ P0 ] ? PSR_q[ S ] : PSR_q[ Z ] ) : ( din[ P0 ] ? PSR_q[ C ] : 1 ) ) );

	// Port 1 always reads dest reg
	wire [15:0] RF_dout;

	if ( IR_q[ `i_rDst ] == 4'hF )  // this if-statement would be inside always @(*)

		RF_dout = PC_q;

	else

		RF_dout = RF_q[ IR_q[ `i_rDst ] ] & { 16 { ( IR_q[ `i_rDst ] != 4'h0 ) } };

	// Port 2 always reads source reg
	wire [15:0] RF_w_p2;

	if ( IR_q[ `i_rSrc ] == 4'hF )  // this if-statement would be inside always @(*)

		RF_w_p2 = PC_q;

	else

		RF_w_p2 = RF_q[ IR_q[ `i_rSrc ] ] & { 16 { ( IR_q[ `i_rSrc ] != 4'h0 ) } };

	// One word instructions operand comes from register file  ??
	wire [15:0] operand;

	if ( IR_q[ `i_length ]              ||  // has immediate
	     IR_q[ IR_LD ]                  ||  // ...
	     ( op == INC ) || ( op == DEC ) ||  // ...
	     IR_q[ IR_WBK ]                 ||  // ...
	    )

		operand = OR_q;

	else

		operand = RF_w_p2;  // ...


	assign rnw = ! ( FSM_q == WRMEM );

	assign dout = RF_w_p2;

	wire [15:0] address_;
	assign address = address_;

	if ( FSM_q == WRMEM || FSM_q == RDMEM )

		if ( op == POP )

			address_ = RF_dout;  // ... ??

		else

			address_ = OR_q;     // ...

	else

		address_ = PC_q;


	assign vpa = ( FSM_q == FETCH0 ) || ( FSM_q == FETCH1 ) || ( FSM_q == EXEC );  // accessing program memory

	assign { vda, vio } = {

		{ 2 { ( FSM_q == RDMEM ) || ( FSM_q == WRMEM ) } }  // accessing data memory

		&

		{
		  ! ( ( op == IN ) || ( op == OUT ) ),  // is not IO instruction
		      ( op == IN ) || ( op == OUT )     // is IO instruction
		}
	};


	always @ ( * ) begin

		// Arithmetic
		case ( op )

			AND, OR                  : { carry, result } = {
			                                                 PSR_q[ C ],
			                                                 ( IR_q[8] ) ? ( RF_dout & operand ) :
			                                                               ( RF_dout | operand )
			                                               };

			ADD, ADC, INC            : { carry, result } = RF_dout + operand + ( IR_q[ 8 ] & PSR_q[ C ] );

			SUB, SBC, CMP, CMPC, DEC : { carry, result } = RF_dout +
			                                               ( operand ^ 16'hFFFF ) +  // two's complement
			                                               ( ( IR_q[8] ) ? PSR_q[ C ] : 1 );

			XOR, GETPSR              : { carry, result } = IR_q[ IR_NOPRED ] ? {
			                                                                     PSR_q[ C ],
			                                                                     8'b0,
			                                                                     PSR_q
			                                                                   }
			                                                                 :
			                                                                   {
			                                                                     PSR_q[ C ],
			                                                                     RF_dout ^ operand
			                                                                   };

			NOT, BSWP                : { carry, result } = IR_q[10] ? {
			                                                            PSR_q[ C ],
			                                                            ~ operand
			                                                          }
			                                                        :
			                                                          {
			                                                            PSR_q[ C ],
			                                                            operand[7:0],
			                                                            operand[15:8]
			                                                          };

			ROR, ASR, LSR            : { result, carry } = {
			                                                 ( IR_q[10] == 0 ) ? PSR_q[ C ] :  // rotate through carry (shift in carry)
			                                                 ( IR_q[8] == 1 ) ? operand[15] :  // arithmetic shift     (shift in sign)
			                                                 1'b0,                             // logical shift        (shift in zero)
			                                                 operand
			                                               };
	
			// LD,MOV,STO,JSR,IN,OUT,PUSH,POP and everything else
			default                  : { carry, result } = {
			                                                 PSR_q[ C ],
			                                                 operand      // ED
			                                               };

		endcase

		// Status bits
		if ( op == SETPSR )

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

			pred_q <= ( FSM_q == FETCH0 ) ? pred_din : pred_d;  // why pred_q FF ??

			// metastability?
			reset_s0_b <= reset_b;
			reset_s1_b <= reset_s0_b;

			if ( ! reset_s1_b ) begin

				PC_q   <= 0;
				PCI_q  <= 0;
				PSRI_q <= 0;
				PSR_q  <= 0;
				FSM_q  <= 0;  // FETCH0

			end

			else begin

				case ( FSM_q )

					FETCH0 : begin

						if ( din[ `i_length ] )  // get immediate

							FSM_q <= FETCH1;

						else if ( ! pred_din )   // NOP

							FSM_q <= FETCH0;

						else if ( ( din[ `i_opcode ] == LD ) || ( din[ `i_opcode ] == STO ) ||
					              ( op_d == PUSH ) || ( op_d == POP ) )   // calculate memory address

							FSM_q <= EAD;

						else

							FSM_q <= EXEC;

					end
	
					FETCH1 : begin

						if ( ! pred_q )

							FSM_q <= FETCH0;

						else if ( ( IR_q[ `i_rDst ] != 0 ) ||
					              ( IR_q[ IR_LD ] ) || IR_q[ IR_STO ] )  // ...

							FSM_q <= EAD;

						else

							FSM_q <= EXEC;

					end
	
					EAD : begin

						if ( IR_q[ IR_LD ] )

							FSM_q <= RDMEM;

						else if ( IR_q[ IR_STO ] )

							FSM_q <= WRMEM;

						else

							FSM_q <= EXEC;

					end
	
					EXEC : begin

						if ( ( ! ( & int_b ) & PSR_q[ EI ] ) ||    // hardware interrupt
						     ( ( op == SETPSR ) && ( | swiid ) )   // software interrupt
						   )

							FSM_q <= INT;

						else if ( ( IR_q[ `i_rDst ] == 4'hF ) || ( op == JSR ) )  // set PC

							FSM_q <= FETCH0;

						else if ( din[ `i_length ] )

							FSM_q <= FETCH1;

						else if ( ( din[ `i_opcode ] == LD ) || ( din[ `i_opcode ] == STO ) ||
					              ( op_d == PUSH ) || ( op_d == POP )
					            )

							FSM_q <= EAD;

						else if ( pred_d )

							FSM_q <= EXEC;

						else

							FSM_q <= FETCH0;

					end

					WRMEM : begin

						if ( ! ( & int_b ) & PSR_q[ EI ] )  // hardware interrupt (active low) and interrupts enabled

							FSM_q <= INT;

						else

							FSM_q <= FETCH0;

					end

					default : begin  // Applies to INT and RDMEM plus undefined states

						if ( FSM_q == RDMEM )

							FSM_q <= EXEC;

						else

							FSM_q <= FETCH0;

					end

				endcase 


				// Operand register input
				if ( ( FSM_q == FETCH0 ) || ( FSM_q == EXEC ) )

					OR_q <= (

						{ 16 { op_d == PUSH } }                                           // 1111111111111111  (-1)
						^ 
						{
						  12'b0,
						  ( op_d == DEC ) || ( op_d == INC ) ? din[ `i_rSrc ]             // 000000000000xxxx  (rSrc as 4 bit immediate)
						                                     : { 3'b0, ( op_d == POP ) }  // 0000000000000001  (1)
						}
					)

				else if ( FSM_q == EAD )

					OR_q <= RF_w_p2 + OR_q;

				else

					OR_q <= din;


				// Program counter
				if ( FSM_q == INT ) begin

					PC_q        <= ( ! int_b[1] ) ? INT_VECTOR1 : INT_VECTOR0;  // jump to interrupt handler
					PCI_q       <= PC_q;                                        // save program counter
					PSRI_q      <= PSR_q[3:0];                                  // save status register
					PSR_q[ EI ] <= 1'b0;                                        // Always clear EI on taking interrupt

				end

				else if ( ( FSM_q == FETCH0 ) || ( FSM_q == FETCH1 ) ) begin

					PC_q <= PC_q + 1;

				end

				else if ( FSM_q == EXEC ) begin

					// PC_q
					if ( op == RTI )                                          // restore program counter

						PC_q <= PCI_q;

					else if ( ( IR_q[ `i_rDst ] == 4'hF ) || ( op == JSR ) )  // set program counter (jump)

						PC_q <= result;

					else if ( ( ! ( & int_b ) & PSR_q[ EI ] ) ||    // hardware interrupt
					          ( ( op == SETPSR ) && ( | swiid ) )   // software interrupt
					        )

						PC_q <= PC_q;                                         // no change

					else                                                      // increment

						PC_q <= PC_q + 1;


					// PSR_q
					if ( op == RTI )       // restore status register

						PSR_q <= {
					               4'b0,   // clear SWI bits on RTI
					               PSRI_q
					             };

					else                   // default...

						PSR_q <= { swiid, enable_int, sign, carry, zero };

				end

				// regFile input
				if ( ( ( FSM_q == EXEC ) &&
				       ! ( ( op == CMP ) || ( op == CMPC ) )            // EXEC and not CMPX
				     )
				     ||
				     ( 
				       ( ( FSM_q == WRMEM ) || ( FSM_q == RDMEM ) ) &&
				       IR_q[ IR_WBK ]                                   // RD/WRMEM and not PUSH/POP
				     )
				   )

					if ( op == JSR )

						RF_q[ IR_q[ `i_rDst ] ] <= PC_q;

					else

						RF_q[ IR_q[ `i_rDst ] ] <= result;


				// Set instruction register including extra bits [19:16]
				if ( ( FSM_q == FETCH0 ) || ( FSM_q == EXEC ) )

					IR_q <= {

						( op_d == PUSH ) || ( op_d == POP ),              // IR_WBK    (19)
						( din[ `i_predicate ] == 3'b001 ),                // IR_NOPRED (18)
						( din[ `i_opcode ] == STO ) || ( op_d == PUSH ),  // IR_STO    (17)
						( din[ `i_opcode ] == LD ) || ( op_d == POP ),    // IR_LD     (16)
						din                                               // (15..0)
					};

				else if ( ( FSM_q == EAD && ( IR_q[ IR_LD ] || IR_q[ IR_STO ] ) ) ||
				          ( FSM_q == RDMEM )
				        )

					// Swap source/dest reg in EA for reads and writes for
					//  writeback of 'source' in push/pop .. swap back again in RDMEM
					IR_q[7:0] <= {
					               IR_q[ `i_rDst ],
					               IR_q[ `i_rSrc ]
					             };
				end

			end 
		end

endmodule

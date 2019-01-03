import sys, re

mnemonics = [

	"mov",
	"and",
	"or",
	"xor",
	"add",
	"adc",
	"sto",
	"ld",
	"ror",
	"jsr",
	"sub",
	"sbc",
	"inc",
	"lsr",
	"dec",
	"asr",
	"halt",
	"bswp",
	"putpsr",
	"getpsr",
	"rti",
	"not",
	"out",
	"in",
	"push",
	"pop",
	"cmp",
	"cmpc",
]

op  = dict( [ ( opcode, mnemonics.index( opcode ) ) for opcode in mnemonics ] )
dis = dict( [ ( mnemonics.index( opcode ), opcode ) for opcode in mnemonics ] )
pred_dict = {

	0 : "",
	1 : "0.",
	2 : "z.",
	3 : "nz.",
	4 : "c.",
	5 : "nc.",
	6 : "mi.",
	7 : "pl."
}


def print_memory_access( type, address, data):

	ch = '{}'.format( chr( data ) ) if ( 0x1F < data < 0x7F ) else '.'

	print( "%5s:   Address : 0x%04x (%5d)         :        Data : 0x%04x (%5d) %s" % ( type, address, address, data, data, ch ) )


def main ():

	if len( sys.argv ) > 3:

		with open( sys.argv[ 3 ], "r" ) as f:

			input_text = iter( ''.join( f.readlines() ) )

	else:
		
		input_text = iter( [ chr( 0 ) ] * 100000 )


	with open( sys.argv[ 1 ], "r" ) as f: 

		wordmem = [ ( int( x, 16 ) & 0xFFFF ) for x in f.read().split() ]

		# initialise machine state inc PC = reg[15]
		regfile   = [ 0 ] * 16
		acc       = 0
		c         = 0
		z         = 0
		pcreg     = 15
		c_save    = 0
		s         = 0
		ei        = 0
		swiid     = 0
		interrupt = 0
		iomem     = [ 0 ] * 65536

		print ( "PC   : Mem       : Instruction            : SWI I S C Z : {}\n{}".format(

			''.join( [ " r%2d " % d for d in range( 0, 16 ) ] ),
			'-' * 130
		) )

	while True:

		pc_save       = regfile[ pcreg ]
		flag_save     = ( swiid, ei, s, c, z )
		regfile[ 0 ]  = 0  # always overwrite regfile location 0 and then dont care about assignments
		preserve_flag = False

		instr_word = wordmem[ regfile[ pcreg ] & 0xFFFF ] &  0xFFFF

		p0 = ( instr_word & 0x8000 ) >> 15
		p1 = ( instr_word & 0x4000 ) >> 14
		p2 = ( instr_word & 0x2000 ) >> 13

		opcode = (
			( ( instr_word & 0xF00 ) >> 8 )
			|
			( 0x10 if ( p0, p1, p2 ) == ( 0, 0, 1 ) else
			 0x00
			)
		)
		source = ( instr_word & 0xF0 ) >> 4
		dest   = instr_word & 0xF

		instr_len     = 2 if ( instr_word & 0x1000 ) else 1
		rdmem         = opcode in ( op[ "ld" ], op[ "in" ], op[ "pop" ] )
		preserve_flag = dest == pcreg

		if ( instr_len == 2 ):

			operand = wordmem[ regfile[ pcreg ] + 1 ]

		else:

			if opcode in [ op[ "inc" ], op[ "dec" ] ]:

				operand = source

			else:

				operand = (
					( opcode == op[ "pop" ] ) -
					( opcode == op[ "push" ] )
				)

		instr_str = "{}{} r{},".format(

			pred_dict[ p0 << 2 | p1 << 1 | p2 ] if ( p0, p1, p2 ) != ( 0, 0, 1 ) else "",
			dis[ opcode ],
			dest
		)

		instr_str += ( "{}{}{}".format(

			"r" if opcode not in ( op[ "inc" ], op[ "dec" ] ) else "",
			source,
			",0x%04x" % operand ) if instr_len == 2 else ""
		)

		if ( opcode in ( op[ "putpsr" ], op[ "getpsr" ] ) ):

			instr_str = re.sub( "r0", "psr", instr_str, 1 )

		mem_str = " %04x %4s " % (

			instr_word,
			"%04x" % ( operand ) if instr_len == 2 else ''
		)

		if opcode in ( op[ "inc" ], op[ "dec" ] ):

			source  = 0

		regfile[ 15 ] += instr_len

		# EA_ED must be computed after PC is brought up to date
		eff_addr = ( regfile[ source ] +
			         operand * ( opcode != op[ "pop" ] )
			       ) & 0xFFFF

		if ( opcode in ( op[ "ld" ], op[ "pop" ] ) ):
			
			ea_ed = wordmem[ eff_addr ]

		elif rdmem:

			ea_ed = iomem[ eff_addr ]

		else:

			ea_ed = eff_addr

		if opcode == op[ "in" ]:

			try:

				ea_ed = ord( input_text.__next__() )

			except:

				ea_ed = 0

		if interrupt : # software interrupts dont care about EI bit

			interrupt        = 0
			regfile[ pcreg ] = 0x0002
			pc_int           = pc_save
			psr_int          = ( swiid, ei, s, c, z )
			ei               = 0

		else:

			print ( "%04x :%s: %-22s :  %1X  %d %d %d %d : %s" % (

				pc_save,
				mem_str,
				instr_str,
				swiid ,ei,
				s,
				c,
				z,
				' '.join( [ "%04x" % i for i in regfile ] )
			) )

			temp0 = bool( c if p0 == 1 else 1 )  # ??
			temp1 = bool( s if p0 == 1 else z )  # ??
			temp2 = temp0                        # ??
			if p1 == 1:

				temp2 = temp1

			if ( ( p0, p1, p2 ) == ( 0, 0, 1 ) ) or ( bool( p2 ) ^ temp2 ):

				if opcode == op[ "halt" ]:

					print( "Stopped on halt instruction at %04x with halt number 0x%04x" % (

						regfile[ 15 ] - ( instr_len ),
						operand
					) )

					break

				elif opcode == op[ "rti" ] and ( dest == 15 ):

					preserve_flag    = True
					regfile[ pcreg ] = pc_int
					flag_save        = ( 0, psr_int[ 1 ], psr_int[ 2 ], psr_int[ 3 ], psr_int[ 4 ] )

				elif opcode in ( op[ "and" ], op[ "or" ], op[ "xor" ] ):

					if opcode == op[ "and" ]:

						regfile[ dest ] = regfile[ dest ] & ea_ed

					elif opcode == op[ "or" ]:

						regfile[ dest ] = regfile[ dest ] | ea_ed

					else:

						regfile[ dest ] = regfile[ dest ] ^ ea_ed

					regfile[ dest ] &= 0xFFFF

				elif opcode in ( op[ "ror" ], op[ "asr" ], op[ "lsr" ] ):

					c = ea_ed & 0x1

					if opcode == op[ "ror" ]:

						regfile[ dest ] = ( c << 15 )

					if opcode == op[ "asr" ]:

						regfile[ dest ] = ea_ed & 0x8000

					else:

						regfile[ dest ] = 0

					regfile[ dest ] |= ( ea_ed & 0xFFFF ) >> 1

				elif opcode in ( op[ "add" ], op[ "adc" ], op[ "inc" ] ):

					res = (
						regfile[ dest ] +
						ea_ed           +
						( c if opcode == op[ "adc" ] else 0 )
					)
					res &= 0x1FFFF

					c = ( res >> 16 ) & 1

					regfile[ dest ] = res & 0xFFFF

				elif opcode in ( op[ "mov" ], op[ "ld" ], op[ "not" ], op[ "in" ], op[ "pop" ] ):

					if opcode == op[ "pop" ]:

						regfile[ source ] = regfile[ source ] + operand
						regfile[ source ] &= 0xFFFF

					if opcode == op[ "not" ]:

						regfile[ dest ] = ~ ea_ed

					else:

						regfile[ dest ] = ea_ed

					regfile[ dest ] &= 0xFFFF

					if opcode in ( op[ "ld" ], op[ "in" ], op[ "pop" ] ):

						print_memory_access( "IN" if opcode == op[ "in" ] else "LOAD", eff_addr, ea_ed )

				elif opcode in (op[ "sub" ], op[ "sbc" ], op[ "cmp" ], op[ "cmpc" ], op[ "dec" ] ) :

					res = (
						regfile[ dest ]          +
						( ( ~ ea_ed ) & 0xFFFF ) +
						( c if ( opcode in ( op[ "cmpc" ], op[ "sbc" ] ) ) else 1 )
					)
					res &= 0x1FFFF

					# retarget r0 with result of comparison
					if opcode in ( op[ "cmp" ], op[ "cmpc" ] ):

						dest = 0

					c = ( res >> 16 ) & 1

					regfile[ dest ] = res & 0xFFFF

				elif opcode == op[ "bswp" ]:

					regfile[ dest ] = ( ( ( ea_ed & 0xFF00 ) >> 8 ) | 
					                    ( ( ea_ed & 0x00FF ) << 8 )
					                  ) & 0xFFFF

				elif opcode == op[ "jsr" ]:

					preserve_flag = True

					regfile[ dest ]  = regfile[ pcreg ]
					regfile[ pcreg ] = ea_ed

				elif opcode == op[ "putpsr" ]:

					preserve_flag = True

					flag_save = (

						( ea_ed & 0xF0 ) >> 4,
						( ea_ed & 0x8  ) >> 3,
						( ea_ed & 0x4  ) >> 2,
						( ea_ed & 0x2  ) >> 1,
						( ea_ed & 1    )
					)

					interrupt = ( ea_ed & 0xF0 ) != 0

				elif opcode == op[ "getpsr" ]:

					regfile[ dest ] = (

						( ( swiid & 0xF ) << 4 ) |
					    (            ei   << 3 ) |
					    (            s    << 2 ) |
					    (            c    << 1 ) |
					    z
					)

				elif opcode in ( op[ "sto" ], op[ "push" ] ):

					preserve_flag = True

					if opcode == op[ "push" ]:

						regfile[ source ] = ea_ed

					wordmem[ ea_ed ] = regfile[ dest ]

					print_memory_access( "STORE", ea_ed, regfile[ dest ] )

				elif opcode == op[ "out" ]:

					preserve_flag = True

					# ch = "."

					# if ( 0x1F < regfile[ dest ] < 0x7F ):

					# 	ch = "{}".format( chr( regfile[ dest ] ) )

					iomem[ ea_ed ] = regfile[ dest ]

					print_memory_access( "OUT", ea_ed, regfile[ dest ] )

			if preserve_flag or dest == 0xF:

				( swiid, ei, s, c, z ) = flag_save

			else:

				s = ( regfile[ dest ] >> 15 ) & 1
				z = int( regfile[ dest ] == 0 )


	# Dump memory for inspection if required
	if len( sys.argv ) > 2:

		with open( sys.argv[ 2 ], "w" ) as f:

			f.write( '\n'.join( [ ''.join( "%04x " % d for d in wordmem[ j : j + 16 ] ) for j in [ i for i in range( 0, len( wordmem ), 16 ) ] ] ) )


if __name__ == "__main__":

	main()

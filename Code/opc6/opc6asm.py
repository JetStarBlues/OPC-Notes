import sys, re, codecs

'''
ppp l oooo ssss dddd  nnnnnnnnnnnnnnnn
  \  \   \    \   \           \_______ 16b optional operand word
   \  \   \    \___\__________________  4b source and destination registers
    \  \___\__________________________  1b instruction length + 4b opcode
     \________________________________  3b predicate bits
'''

op = [

	'mov',
	'and',
	'or',
	'xor',
	'add',
	'adc',
	'sto',
	'ld',
	'ror',
	'jsr',
	'sub',
	'sbc',
	'inc',
	'lsr',
	'dec',
	'asr',
	'halt',
	'bswp',
	'putpsr',
	'getpsr',
	'rti',
	'not',
	'out',
	'in',
	'push',
	'pop',
	'cmp',
	'cmpc',
]

symbolTable = {
    
	'r0'  : 0,
	'r1'  : 1,
	'r2'  : 2,
	'r3'  : 3,
	'r4'  : 4,
	'r5'  : 5,
	'r6'  : 6,
	'r7'  : 7,
	'r8'  : 8,
	'r9'  : 9,
	'r10' : 10,
	'r11' : 11,
	'r12' : 12,
	'r13' : 13,
	'r14' : 14,
	'r15' : 15,
	'psr' : 0,
	'pc'  : 15,
}

predicateDict = {

	# 0x2000 001............. reseved for non-predicated instuctions

	'1'  : 0x0000,  # 000............. always execute
	''   : 0x0000,  # 000............. always execute
	'z'  : 0x4000,  # 010............. execute if zero flag set
	'nz' : 0x6000,  # 011............. execute if zero flag is clear
	'c'  : 0x8000,  # 100............. execute if carry flag is set
	'nc' : 0xA000,  # 101............. execute if carry flag is clear
	'mi' : 0xC000,  # 110............. execute if sign flag is set
	'pl' : 0xE000,  # 111............. execute if sign flag is clear
}

wordmem   = [ 0x0000 ] * 64 * 1024
macro     = dict()
macroname = None
newtext   = []
wcount    = 0
errors    = []
warnings  = []
reg_re    = re.compile( '(r\d*|psr|pc)' )
mnum      = 0
nextmnum  = 0


# recursively expand macros, passing on instances not (yet) defined
def expand_macro( line, macro, mnum ):

	global nextmnum

	text = [ line ]

	mobj_re = '''
		^                     # newline
		(?P<label>            # named subgroup
			\w*\:                # zero or more words followed by ':'
		)
		?                        # one or more of this group
		\s*                   # whitespace
		(?P<name>             # named subgroup
			\w+                  # one or more words
		)
		\s*?                  # non-greedy whitepace ??
		\(
		(?P<params>           # named subgroup
			.*?                   # anything, non-greedy ??
		)
		\)
	'''
	mobj_re = re.compile( mobj_re, re.X )

	mobj = re.match( mobj_re, line )

	if mobj and mobj.groupdict()[ 'name' ] in macro:

	label    = mobj.groupdict()[ 'label'  ]
	instname = mobj.groupdict()[ 'name'   ]
	paramstr = mobj.groupdict()[ 'params' ]

	text       = [ '#{}'.format( line ) ]
	instparams = [ x.strip() for x in paramstr.split( ',' ) ]
	mnum       = nextmnum
	nextmnum   = nextmnum + 1

	if label:

		text.append( '{}{}'.format(

			label,

			':' if ( label != ''     and
			         label != 'None' and
			         not ( label.endswith( ':' ) )
			        )
			else ''
		) )

	for newline in macro[ instname ][ 1 ]:

		for s, r in zip( macro[ instname ][ 0 ], instparams ):

			newline = ( newline.replace( s, r ) if s else newline )

			newline = newline.replace( '@', '{}_{}'.format( instname, mnum ) )

		text.extend( expand_macro( newline, macro, nextmnum ) )

	return text

def assemble( _inputFile ):

	# Pass 0 - macro expansion
	for line in open( _inputFile, "r" ).readlines():

		mobj =  re.match( "\s*?MACRO\s*(?P<name>\w*)\s*?\((?P<params>.*)\)", line, re.IGNORECASE )

		if mobj:

			macroname          = mobj.groupdict()[ "name" ]
			macro[ macroname ] = (

				[ x.strip() for x in ( mobj.groupdict()[ "params" ] ).split ("," ) ],
				[]
			)

		elif re.match( "\s*?ENDMACRO.*", line, re.IGNORECASE ):

			macroname = None
			line      = '# ' + line

		elif macroname:

			macro[ macroname ][ 1 ].append( line )

		newtext.extend( expand_macro( ( '' if not macroname else '# ' ) + line, macro, mnum ) )

	# Two pass assembly
	for iteration in range ( 0, 2 ):

		wcount  = 0
		nextmem = 0

		for line in newtext:

			mobj_re = '''
				^                     # newline
				(?:
					(?P<label>
						\w+
					)
				:)?
				\s*
				(
					(?:
						(?P<pred>
							((pl)|(mi)|(nc)|(nz)|(c)|(z)|(1)?)?
						)
						\.
					)
				)?
				(?P<inst>
					\w+
				)?
				\s*
				(?P<operands>
					.*
				)
			'''
			mobj_re = re.compile( mobj_re, re.X )

			mobj = re.match( mobj_re, re.sub( "#.*", "", line ) )

			( label, pred, inst, operands ) = [ mobj.groupdict()[ item ] for item in ( "label", "pred", "inst", "operands" ) ]

			pred     = "1" if pred == None else pred
			opfields = [ x.strip() for x in operands.split( "," ) ]
			words    = []
			memptr   = nextmem

			if ( iteration == 0 and
			     ( label and label != "None" ) or
			     ( inst == "EQU" )
			   ):

				if label in symtab:

					errors += [ "Error: Symbol %16s redefined in ...\n         %s" % ( label, line.strip() ) ]

				if label != None:

					exec ( 

						"%s= int(%s)" % ( label, str( nextmem ) ),
						globals(),
						symtab
					)

				else:

					exec ( 

						"%s= int(%s)" % ( opfields[0], opfields[1] ),
						globals(),
						symtab
					)

			if ( inst in ( "WORD", "BYTE" ) or
			     inst in op
			   ) and iteration < 1:

				# If two operands are provide instuction will be one word  ??
				if inst == "WORD":

					nextmem += len( opfields )

				elif inst == "BYTE":

					nextmem += ( len( opfields ) + 1 ) // 2

				else:

					nextmem += len( opfields ) - 1

			elif inst in op or inst in ( "BYTE", "WORD", "STRING", "BSTRING", "PBSTRING" ):

				if inst in ( "STRING", "BSTRING", "PBSTRING" ):

					strings = re.match(

						'.*STRING\s*\"(.*?)\"(?:\s*?,\s*?\"(.*?)\")?(?:\s*?,\s*?\"(.*?)\")?(?:\s*?,\s*?\"(.*?)\")?.*?',
						line.rstrip()
					)

					string_data = codecs.decode(

						''.join( [ x for x in strings.groups() if x != None ] ),
						'unicode_escape'
					)

					string_len = ''

					if inst == "PBSTRING":

						string_len = chr( len( string_data ) & 0xFF )  # limit string length to 255 for PBSTRINGS

					step    = 2 if inst in ( "BSTRING", "PBSTRING" ) else 1
					wordstr = string_len + string_data + chr( 0 )

					words = [ ( ord( wordstr[i] ) |
					            ( ( ord( wordstr[ i + 1 ] ) << 8 ) if inst in ( "BSTRING", "PBSTRING" ) else 0 )
					          )
					          for i in range( 0, len( wordstr ) - 1, step )
					]

				else:

					if ( ( len( opfields ) == 2 and not reg_re.match( opfields[ 1 ] ) ) and
						 inst not in ( "inc", "dec", "WORD", "BYTE" )
					   ):

						warnings.append( "Warning: suspected register field missing in ...\n         %s" % ( line.strip() ) )

					try:

						# calculate PC as it will be in EXEC state
						exec(
							"PC=%d+%d" % ( nextmem, len( opfields ) - 1 ),
							globals(),
							symtab
						)

						words = [ int( eval( f, globals(), symtab ) ) for f in opfields ]

						# pad out BYTE lines wih a single zero
						if inst == "BYTE":

							words += [0]

							# pack bytes 2 to a word

							words = [ ( words[ i + 1 ] & 0xFF ) << 8 |
							          ( words[ i ] & 0xFF )
							          for i in range( 0, len( words ) - 1, 2 )
							]

					except ( ValueError, NameError, TypeError, SyntaxError ):

						words = [0] * 3
						errors += [ "Error: illegal or undefined register name or expression in ...\n         %s" % line.strip() ]

					if inst in op:

						( dst, src, val, abs_src ) = (

							( words + [0] )[ : 3 ] +
							[ words[1] if words[1] > 0 else - words[1] ]
						)

						if ( inst in ( "inc", "dec" ) and
						     abs_src > 0xF
						   ):

							errors += [ "Error: short constant out of range in ...\n         %s" % ( line.strip() ) ]

						if ( inst in ( "inc", "dec" ) and
						     src & 0x8000
						   ):

							inst = 'dec' if inst == 'inc' else 'inc'
							src = ( ~ src + 1 ) & 0xF

						words = [

							( ( len( words ) == 3 ) << 12 ) |
							( pdict[ pred ] if ( ( op.index( inst ) & 0x10 ) == 0 ) else 0x2000 ) |
							( ( op.index( inst ) & 0x0F ) << 8 ) |
							( src << 4 ) |
							dst,
							val & 0xFFFF
						][ : len( words ) - ( len( words ) == 2 ) ]

				wordmem[ nextmem : nextmem + len( words ) ] = words
				nextmem = nextmem + len( words )
				wcount  = wcount + len( words )

			elif inst == "ORG":

				nextmem = eval( operands, globals(), symtab )

			elif inst and ( inst != "EQU" ) and iteration>0 :

				errors.append( "Error: unrecognized instruction or macro %s in ...\n         %s" % ( inst, line.strip() ) )

			if iteration > 0 :

				print( "%04x  %-20s  %s" % (

					memptr,
					' '.join( [ ( "%04x" % i ) for i in words ] ),
					line.rstrip()
				) )

	print ( "\nAssembled %d words of code with %d error%s and %d warning%s." % (

		wcount,
		len( errors ),
		'' if len( errors ) == 1 else 's',
		len( warnings ),
		'' if len( warnings ) == 1 else 's'
	) )

	print ( "\nSymbol Table:\n\n%s\n\n%s\n%s" % (

		'\n'.join(

			[ "%-32s 0x%04X (%06d)" % ( k, v, v ) for k, v in sorted( symtab.items() ) if not re.match( "r\d|r\d\d|pc|psr", k ) ]
		),
		'\n'.join( errors ),
		'\n'.join( warnings )
	) )

	return wordmem

def genOutputFile( wordmem, _outputFile ):

	# Write to hex file only if no errors else send result to null file
	if len( errors ) > 0:

		outputFile = "/dev/null"

	else:

		outputFile = _outputFile

	with open( outputFile, "w" ) as f:   

		f.write(

			'\n'.join(

				[
					''.join(

						"%04x " % d for d in wordmem[ j : j + 24 ]
					)
					for j in [ i for i in range( 0, len( wordmem ), 24 ) ]
				]
			)
		)


if __name__ == "__main__":

	inputFile  = sys.argv[ 1 ]
	outputFile = sys.argv[ 2 ]

	genOutputFile( assemble( inputFile ), outputFile )

	sys.exit( len( errors ) > 0 )
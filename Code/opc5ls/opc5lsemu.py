import sys, re

mnemonics = "mov,and,or,xor,add,adc,sto,ld,ror,not,sub,sbc,cmp,cmpc,bswp,psr,halt".split(',')  # halt aliassed to mov modulo 16
mnemonics += [""]*14
mnemonics += ["rti"]

op = dict([(opcode,mnemonics.index(opcode)) for opcode in mnemonics])
dis = dict([(mnemonics.index(opcode),opcode) for opcode in mnemonics])

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

with open(sys.argv[1],"r") as f:
	wordmem = [ (int(x,16) & 0xFFFF) for x in f.read().split() ]

(regfile, acc, c, z, pcreg, c_save, s, ei, swiid, stdout, interrupt) = ([0]*16,0,0,0,15,0,0,0,0,"",0) # initialise machine state inc PC = reg[15]

print ("PC   : Mem       : Instruction            : SWI I S C Z : %s\n%s" % (''.join([" r%2d " % d for d in range(0,16)]), '-'*137))

while True:

	pc_save       = regfile[pcreg]
	flag_save     = (swiid,ei,s,c,z)
	regfile[0]    = 0                 # always overwrite regfile location 0 and then dont care about assignments
	preserve_flag = False

	instr_word = wordmem[regfile[pcreg]] & 0xFFFF

	(p0, p1, p2) = ( (instr_word & 0x8000) >> 15, (instr_word & 0x4000) >> 14, (instr_word & 0x2000) >> 13)

	(opcode, source, dest) = ((instr_word & 0xF00) >> 8, (instr_word & 0xF0) >> 4, instr_word & 0xF)

	instr_len = 2 if (instr_word & 0x1000) else 1

	rdmem = opcode == op["ld"]

	operand = wordmem[ regfile[pcreg] + 1 ] if ( instr_len == 2 ) else 0

	instr_str = "%s%s r%d,r%d" % (

		pred_dict[ p0<<2 | p1<<1 | p2 ],
		dis[opcode],
		dest,
		source
	)
	instr_str = re.sub(  "r0",  "psr", instr_str, 1 ) if (opcode==op["psr"] and dest!=15)          else instr_str
	instr_str = re.sub( "psr",  "rti", instr_str    ) if (opcode==op["psr"] and dest==15)          else instr_str
	instr_str = re.sub(  "ld", "halt", instr_str    ) if (opcode==op["mov"] and (dest==source==0)) else instr_str
	instr_str += (",0x%04x" % operand) if instr_len==2 else ''

	mem_str = " %04x %4s " % (instr_word, "%04x" % (operand) if instr_len==2 else '')

	regfile[15] += instr_len  # EA_ED must be computed after PC is brought up to date

	if rdmem:

		ea_ed = wordmem[ ( regfile[source] + operand ) & 0xFFFF ]

	else:

		ea_ed = ( regfile[source] + operand ) & 0xFFFF

	if interrupt: # software interrupts dont care about EI bit

		interrupt      = 0
		regfile[pcreg] = 0x0002
		pc_int         = pc_save
		psr_int        = (swiid,ei,s,c,z)
		ei             = 0

	else:

		print ("%04x :%s: %-22s :  %1X  %d %d %d %d : %s" % (

			pc_save,
			mem_str,
			instr_str,
			swiid, ei, s, c, z,
			' '.join( ["%04x" % i for i in regfile] )
		) )

		if ( bool(p2) ^ ( bool(s if p0==1 else z) if p1==1 else bool(c if p0==1 else 1))):

			if opcode == (op["halt"]&0x0F) and (source==dest==0):

				print("Stopped on halt instruction at %04x with halt number 0x%04x" % (regfile[15]-(instr_len), operand) )
				break

			elif opcode == (op["rti"]&0xF) and (dest==15):

				regfile[pcreg] = pc_int
				flag_save      = (0,psr_int[1],psr_int[2],psr_int[3],psr_int[4])
				preserve_flag  = True

			elif opcode == op["and"]:

				regfile[dest] = (regfile[dest] & ea_ed) & 0xFFFF

			elif opcode == op["or"]:

				regfile[dest] = (regfile[dest] | ea_ed) & 0xFFFF

			elif opcode == op["xor"]:

				regfile[dest] = (regfile[dest] ^ ea_ed) & 0xFFFF

			elif opcode == op["ror"]:

				c             = ea_ed & 0x1
				regfile[dest] = (c<<15) | ((ea_ed&0xFFFF) >> 1)

			elif opcode in (op["add"], op["adc"]) :

				res           = (regfile[dest] + ea_ed + (c if opcode==op["adc"] else 0)) & 0x1FFFF
				c             = (res>>16) & 1
				regfile[dest] = res & 0xFFFF

			elif opcode in (op["mov"], op["ld"], op["not"]):

				regfile[dest] = ( ~ ea_ed if opcode==op["not"] else ea_ed ) & 0xFFFF

			elif opcode in (op["sub"], op["sbc"], op["cmp"], op["cmpc"]) :

				res = (regfile[dest] + ((~ea_ed)&0xFFFF) + (c if (opcode in (op["cmpc"],op["sbc"])) else 1)) & 0x1FFFF
				c   = (res>>16) & 1

				dest = 0 if opcode in( op["cmp"], op["cmpc"] ) else dest # retarget r0 with result of comparison

				regfile[dest] = res & 0xFFFF

			elif opcode == op["bswp"]:

				regfile[dest] = (((ea_ed&0xFF00)>>8)|((ea_ed&0x00FF)<<8)) & 0xFFFF

			elif opcode == op["psr"] and dest==0: # putpsr

				preserve_flag = True
				flag_save     = ( (ea_ed&0xF0)>>4, (ea_ed&0x8)>>3, (ea_ed&0x4)>>2, (ea_ed&0x2)>>1, (ea_ed)&1 )
				interrupt     = (ea_ed&0xF0) != 0

			elif opcode == op["psr"] and dest != 15 and source==0: # getpsr

				regfile[dest] = ( (swiid&0xF)<<4 ) | (ei<<3) | (s<<2) | (c<<1) | z

			elif opcode == op["sto"]:

				preserve_flag  = True
				wordmem[ea_ed] = regfile[dest]

				if ea_ed == 0xfe09:

					stdout = chr(regfile[dest])
					print (stdout)

			if (preserve_flag or dest==0xF ):

				(swiid,ei,s,c,z) = flag_save

			else:

				# swiid = swiid
				# ei    = ei
				s     = (regfile[dest]>>15) & 1
				# c     = c
				z     = 1 if (regfile[dest]==0) else 0

if len(sys.argv) > 2:                       # Dump memory for inspection if required
	with open(sys.argv[2],"w" ) as f:
		for i in range(0, len(wordmem), 16):
			f.write( '%s\n' %  ' '.join("%04x"%n for n in wordmem[i:i+16]))

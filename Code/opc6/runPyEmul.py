import os
# import opc6emu

inputFile = 'tests/davefib_int.s'

binFile = 'testsDump/binary'

dumpFile = 'testsDump/memDump'

# Generate binary
print( '\nGenerating binary file' )
os.system( 'python opc6byteasm.py -f {} -o {}'.format( inputFile, binFile ) )

# Run emulator
print( '\nRunning emulation' )
# os.system( 'python opc6emu.py {}'.format( binFile ) )
os.system( 'python opc6emu.py {} {}'.format( binFile, dumpFile ) )

.SUFFIXES: .hex

PROGRAM = lcd

all: ram.mem

ram.mem: $(PROGRAM).hex cnv
	./cnv $<

$(PROGRAM).hex: $(PROGRAM).asm
	asl -cpu 1802 -L $<
	p2hex $(PROGRAM).p

clean:; rm -f $(PROGRAM) a.out *.{s,p,lst,hex} cnv ram.mem

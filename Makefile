rom: iwram-bin iwram-sym rng-pmdred.s
	armips -root . rng-pmdred.s

iwram-sym: iwram-bin
	awk '$$2 ~ /^[^\.@0-9].+/ {print $$2 " equ 0x" $$1}' iwram.sym > iwram.sym.s

iwram-bin: rng-pmdred-iwram.s
	armips -root . -sym2 iwram.sym rng-pmdred-iwram.s

bps: rom
	flips --bps baserom.gba rng-pmdred.gba rng-pmdred.bps

clean:
	rm -f iwram.sym iwram.bin rng-pmdred.gba iwram.sym.s rng-pmdred.bps
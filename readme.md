# rng-pmdred
This is a hack that switches the dungeon random number generator to a different algorithm and works around the quicksave RNG bug in the US/Australia release of *Pokémon Mystery Dungeon - Red Rescue Team*.
## Building
### Requirements
* make
* awk
* armips
* flips (only needed for generating a bps patch)

The base ROM must be in the same folder and be named `baserom.gba`.
### Building
* `make rom`: builds `rng-pmdred.gba`.
* `make bps`: additionally generated `rng-pmdred.bps`.

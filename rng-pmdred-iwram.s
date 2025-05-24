;The Mersenne twister state uses more than 2K of IWRAM space for no good reason.
; Let's blow it on code.

.gba
IWRAM_BASE equ 0x3001198
;iwram.bin is the binary that gets loaded into the former MT state area in RAM
;which contains the actual PRNG code.
.create "iwram.bin", IWRAM_BASE
.area 0x9C0
.arm

ExMTState: .dw 0,0,0,0

DungRand32:
    ; The basic SFC32 random number generator;
    push {r4}
    ldr r12, =DungState
    ldmia r12, {r1-r4}
    ; result = a + b + ctr++
    add r0, r1, r2
    add r0, r0, r4
    add r4, r4, #1
    ; a = b ^ (b << 9)
    eor r1, r2, r2, lsr #9
    ; b = c * 9
    add r2, r3, r3, lsl #3
    ; c = result + rol(c, 21)
    add r3, r0, r3, ror #11
    stmia r12, {r1-r4}
    pop {r4}
    bx lr

DungRand16:
    ; DungeonRand16Bit actually never gets called by the original game except
    ; by other dungeon_random.c routines, but it IS a public function so for
    ; safety I'm implementing it anyway.
    push {lr}
    bl DungRand32
    mov r0, r0, lsr #16
    pop {lr}
    bx lr

DungRandInt:
    ; The new algorithm only works right for positive integers.
    ; If the argument is 0 or negative, do it the old way.
    cmp r0, #0
    ble @@bad
    push {r4-r6}
    ; Calculate a bitmask for more efficient unbiased rejection sampling.
    ; This reduces the worst case repeat probability to 50% for any argument;
    ; usually it is better than that.
    sub r6, r0, #1
    orr r5, r6, r6, lsr #1
    orr r5, r5, r5, lsr #2
    orr r5, r5, r5, lsr #4
    orr r5, r5, r5, lsr #8
    orr r5, r5, r5, lsr #16
    ldr r12, =DungState
    ldmia r12, {r1-r4}
@@loop:
    add r0, r1, r2
    add r0, r0, r4
    add r4, r4, #1
    eor r1, r2, r2, lsr #9
    add r2, r3, r3, lsl #3
    add r3, r0, r3, ror #11
    and r0, r0, r5
    cmp r0, r6
    bhi @@loop
    stmia r12, {r1-r4}
    pop {r4-r6}
    bx lr
@@bad:
    ; This should provide the same results as the original algorithm.
    ; For 0, you get 0, and for negative numbers you kind of get nonsense.
    ; For small negative arguments I think you have a 1/65536 chance of
    ; getting a 0, and otherwise you get 65535. Not very useful!
    push {r4, lr}
    mov r0, r4
    bl DungRand16
    mul r0, r4, r0
    mov r0, r0, asr #16
    mov r0, r0, lsl #16
    mov r0, r0, lsr #16
    pop {r4, lr}
    bx lr

DungRandRange:
    cmp r1, r0
    bxeq lr ; if r1 == r0, just return r0
    blt @@swap  ; swap r1 and r0 if r1 is less than r0
@@ok:
    push {r4-r7}
    ldr r12, =DungState
    ; calculate the bound
    sub r7, r1, r0
    sub r7, r7, #1
    orr r5, r7, r7, lsr #1
    orr r5, r5, r5, lsr #2
    orr r5, r5, r5, lsr #4
    orr r5, r5, r5, lsr #8
    orr r5, r5, r5, lsr #16

    ldmia r12, {r1-r4}
@@loop:
    ; bitmasked rejection sampling, as above
    add r6, r1, r2
    add r6, r6, r4
    add r4, r4, #1
    eor r1, r2, r2, lsr #9
    add r2, r3, r3, lsl #3
    add r3, r6, r3, ror #11
    and r6, r6, r5
    cmp r6, r7
    bhi @@loop
    stmia r12, {r1-r4}
    add r0, r0, r6
    pop {r4-r7}
    bx lr
@@swap:
    mov r2, r1
    mov r1, r0
    mov r0, r2
    b @@ok

; bool32 DungRandOutcome(s32 percentChance)
DungRandOutcome:
    push {r4-r8}
    ldr r12, =DungState
    mov r5, #100
    ldmia r12, {r1-r4}
@@loop:
    add r8, r1, r2
    add r8, r8, r4
    add r4, r4, #1
    eor r1, r2, r2, lsr #9
    add r2, r3, r3, lsl #3
    add r3, r8, r3, ror #11
    ; Unbiased multiplication-based rejection sampling.
    ; This method has the advantage of a relatively low reroll probability,
    ; but requires the calculation of 2^32 % upperBound. As upperBound is a
    ; constant in this case, it's more efficient.
    umull r6, r7, r8, r5
    ; did the low 32 bits indicate it's in the biased range?
    cmp r6, #96
    blo @@loop ; yes, try again
    stmia r12, {r1-r4}
    ; return true if r7 is less than the chance
    cmp r7, r0
    movlt r0, #1
    movge r0, #0
    pop {r4-r8}
    bx lr

gDungeon_Loc equ 0x203B418

DungRandInit:
    push {r4}
    ldr r3, =gDungeon_Loc
    ldr r3, [r3]
    add r3, r3, #0x1C400 ;calculate the offset to the DungeonPosition
    add r3, r3, #0x170
    ldr r1, [r3]  ; load the DungeonPosition (type punning)
    mov r2, r0
    mov r3, r0
    mov r4, #1
    ; do the mixing
@@loop:
    add r0, r1, r2
    add r0, r0, r4
    add r4, r4, #1
    eor r1, r2, r2, lsr #9
    add r2, r3, r3, lsl #3
    add r3, r0, r3, ror #11
    cmp r4, #0x11
    bne @@loop
    ldr r12, =DungState
    stmia r12, {r1-r4}
    pop {r4}
    bx lr

DungState: .dw 0, 0, 0, 0
DungRandInitFlag: .dw 0
.pool

.align 32, 0xFF ; (to ensure CpuFastSet can't clobber other regions of IWRAM)
.endarea
.close
.gba
;This includes all of the Thumb code and the ROM patch.

IWRAM_BASE equ 0x3001198
PAD_START equ 0x83A2F00
PAD_END equ 0x83B0000

.open "baserom.gba","rng-pmdred.gba",0x8000000

;insert our IWRAM code binary and the code to load it into a padding area
.org PAD_START
.area PAD_END-PAD_START

.thumb
.align 2
GameLoop equ 0x8000348
Hang equ 0x800d090
; LoadIwramBinary hooks the end of AgbMain.
LoadIwramBinary:
    ldr r0, =IwramBinary
    ldr r1, =IWRAM_BASE
    ldr r2, =filesize("iwram.bin")
    swi 0xC ; CpuFastSet
    bl GameLoop
    bl Hang

.align 4
IwramBinary: .incbin "iwram.bin"

.include "iwram.sym.s"

PrepareQuickSaveRead_Loc equ 0x801277C

; This hook sets the flag that indicates that the dungeon RNG is uninitialized.
PrepareQuickSaveRead_Hook:
    mov r2, #0
    ldr r3, =DungRandInitFlag
    str r2, [r3]
    ldr r2, =(PrepareQuickSaveRead_Loc|1) ; set the 1 bit as this is thumb
    bx r2

PRNGState_Loc equ 0x203B07C
YAR24State_Loc equ 0x203B458
YetAnotherRandom24_Loc equ 0x80840a4
InitYAR24_Loc equ 0x808408C
InitDungeonRNG_Loc equ 0x80840D8
Rand16Bit_Loc equ 0x8006178
gDungeon_Loc equ 0x203B418
; This handles the workaround for the dungeon RNG bug.
; This is not a normal function so don't call it!!
DungeonRngSeedingCode:
    ; HACK: the caller clobbers r0, so we don't need to save it
    push {r1-r4, lr}

    ; used a couple places, so put it in a reg callees won't clobber
    ldr r4, =DungRandInitFlag

    ; Do we think the "dungeon RNG" is initialized?
    ldr r0, [r4]
    cmp r0, #0
    beq @@dungeon_state_init

    ; We do, but this is a floor init step, so we still have to init
    ; the "primary RNG".
    cmp r6, #0
    beq @@primary_state_init

    ; Everything's good, continue onward.
    pop {r1-r4, pc}
@@dungeon_state_init:
    ; just directly read the state.
    ldr r0, =PRNGState_Loc
    ldr r0, [r0]
    ; or with 1 because this is xorshift
    mov r1, #1
    orr r0, r1
    ldr r1, =YAR24State_Loc
    str r0, [r1]
    ; advance the RNG state
    bl Rand16Bit_Loc
    ; fall through
@@primary_state_init:
    ; set the init flag
    mov r0, #1
    str r0, [r4]

    bl YetAnotherRandom24_Loc

    ; write some crap into some memory locations
    ; I have no idea if the game *actually* uses these at all.
    ; calculate *gDungeon+0x668
    ldr r1, =gDungeon_Loc
    ldr r1, [r1]
    ; 0x668 is too large for a thumb constant
    mov r2, #0xCD
    lsl r2, r2, #3
    add r1, r2, r1

    ; write literal 10 to somewhere it should be
    mov r2, #10
    strh r2, [r1]

    ; write the seed to somewhere ELSE it should be
    str r0, [r1, #0x18]

    ; actually init the rng
    bl InitDungeonRNG_Loc
    ; ...and return to RunDungeon_Async
    pop {r1-r4, pc}
.pool
.endarea


;okay, now we begin the inline patches and function replacements

;patch AgbMain to call the load hook
.org 0x800b4b8
.area 0x4
    bl LoadIwramBinary
.endarea

.org 0x8000f18
.area 0x4
    bl PrepareQuickSaveRead_Hook
.endarea

; patch RunDungeon_Async to jump into the patch function
RunDungeon_Async_Start_Loc equ 0x8043324
RunDungeon_Async_Continue_Loc equ 0x8043346
.org RunDungeon_Async_Start_Loc
.area RunDungeon_Async_Continue_Loc-RunDungeon_Async_Start_Loc
    ; DungeonRngSeedingCode actually saves this address
    bl DungeonRngSeedingCode
    b RunDungeon_Async_Continue_Loc
.endarea

DungeonRand16Bit_Loc equ 0x80840E8
DungeonRandInt_Loc equ 0x8084100
DungeonRandRange_Loc equ 0x808411C
DungeonRandOutcome_Loc equ 0x8084144
DungeonRandOutcome_2_Loc equ 0x8084160
CalculateStatusTurns_Loc equ 0x808417C ; not used, only included for area calc

MersenneTwister_InitializeState_Loc equ 0x8094D28
Random32MersenneTwister_Loc equ 0x8094E4C
; These two are only for area calc
MersenneTwister_MixSeeds_Loc equ 0x8094D74
InitializePlayTime_Loc equ 0x8094f88

.org InitYAR24_Loc
.area YetAnotherRandom24_Loc - InitYAR24_Loc
InitYAR24:
    ; This just marks YAR24 as uninitialized so the dungeon rand seeding code
    ; can handle it.
    mov r0, #0
    ldr r1, =DungRandInitFlag
    str r0, [r1]
    bx lr
    .pool
.endarea

.org YetAnotherRandom24_Loc
.area InitDungeonRNG_Loc - YetAnotherRandom24_Loc
YetAnotherRandom24:
    ; a basic full period xorshift32 generator
    ; Quality is not great but this is only used for seeds anyway.
    ldr r2, =YAR24State_Loc
    ldr r0, [r2]
    lsr r1, r0, #6
    eor r0, r1
    lsl r1, r0, #17
    eor r0, r1
    lsr r1, r0, #9
    eor r0, r1
    str r0, [r2]
    bx lr
    .pool
.endarea

.org InitDungeonRNG_Loc
.area DungeonRand16Bit_Loc - InitDungeonRNG_Loc
InitDungeonRNG:
    ldr r1, =DungRandInit
    bx r1
.endarea

.org DungeonRand16Bit_Loc
.area DungeonRandInt_Loc - DungeonRand16Bit_Loc
DungeonRand16Bit:
    ldr r0, =DungRand16
    bx r0
    .pool
.endarea

.org DungeonRandInt_Loc
.area DungeonRandRange_Loc - DungeonRandInt_Loc
DungeonRandInt:
    ldr r1, =DungRandInt
    bx r1
.endarea


.org DungeonRandRange_Loc
.area DungeonRandOutcome_Loc - DungeonRandRange_Loc
DungeonRandRange:
    ldr r2, =DungRandRange
    bx r2
    .pool
.endarea

.org DungeonRandOutcome_Loc
.area DungeonRandOutcome_2_Loc - DungeonRandOutcome_Loc
DungeonRandOutcome:
    ldr r1, =DungRandOutcome
    bx r1
.endarea


.org DungeonRandOutcome_2_Loc
.area CalculateStatusTurns_Loc - DungeonRandOutcome_Loc
DungeonRandOutcome_2:
    b DungeonRandOutcome
    .pool
.endarea

;The former Mersenne twister is barely used at all, so it can be thumb.

.org MersenneTwister_InitializeState_Loc
.area MersenneTwister_MixSeeds_Loc - MersenneTwister_InitializeState_Loc
MersenneTwister_InitializeState:
    push {r4, lr}
    ldr r4, =ExMTState
    mov r1, r0
    mov r2, r0
    mov r3, #7
    stmia r4!, {r0-r3}
    mov r4, #16
@@loop:
    bl Random32MersenneTwister
    sub r4, #1
    bne @@loop
    pop {r4}
    pop {r0}
    bx r0
.endarea

; in case some other patch calls this
.org MersenneTwister_MixSeeds_Loc
.area Random32MersenneTwister_Loc - MersenneTwister_MixSeeds_Loc
MersenneTwister_MixSeeds:
    bx lr
.endarea

.org Random32MersenneTwister_Loc
.area InitializePlayTime_Loc - Random32MersenneTwister_Loc
Random32MersenneTwister:
    ;this isn't the mersenne twister of course
    push {r4-r6}
    mov r6, #11
    ldr r5, =ExMTState
    ldmia r5!, {r1-r4}
    add r1, r1, r2
    add r0, r1, r4
    add r4, r4, #7
    lsr r1, r2, #9
    eor r1, r2
    lsl r2, r3, #3
    add r2, r2, r3
    ror r3, r6
    add r3, r3, r0
    sub r5, #16
    stmia r5!, {r1-r4}
    pop {r4-r6}
    bx lr
    .pool
.endarea

.close

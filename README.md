# Z80Löve

This thingie was inspired by https://abagames.github.io/z80-repl/index.html

## Instructions

Type your assembly instructions when in REPL mode, and they will be assembled at the current PC (but not automatically executed), and the PC advanced.

Instructions involving indirection + offset, such as `(ix+4)`, bit instructions, and selected extended instructions are not implemented yet.

No IN/OUT either.

### Keys

    Cursor keys - move the PC around
    PgUp, PgDown - move the 256 bytes window downwards (+100h) or upwards (-100h)
    F9 - Set PC to 0
    F10 - Step over the instruction at PC
    F1 - Switch to REPL mode
    F2 - Run from PC
    F3 - Save to snapshot.mem
    F4 - Restore from snapshot.mem

### Commands
    \> nnnn - set PC to nnnn
    RUN - Run from PC
    Escape - quit

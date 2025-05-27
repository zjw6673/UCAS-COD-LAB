# custom cpu design (MIPS)

1. add a register to store signals passed in through the valid-ready handshake!
    or it may change once it is received

2. when should PC get updated?
    if PC is updated right after ID state,
    write data that depend on pc (such as PC+8 for jalr) has not been written by then,
    which could lead to error

    two possible solutions:
    1. updated pc later, that is, after WB ans ST state.
    2. make snpc an register, which updates after WB and ST state.
        but since pcnext depends on snpc, thus snpc must be updated before IF arrives
    all ways involves modifying a reg to make it update after WB,ST and before IF.
    so just adopt the most natural one, which is the first one

3. NO, should update pcbefore IF state arrives, or the delay could be fatal on an fpga!

# custom cpu design (RISCV)

1. convert func3 to one-hot encoding
2. pc update sequence: (PC port connects to nextPc)
- during ID, generate snpc and bnpc according to pcReg and inst
- after EX, update nextPc (choose between snpc and bnpc according to aluOut and decode value)
- after IW, update pcReg to nextPc

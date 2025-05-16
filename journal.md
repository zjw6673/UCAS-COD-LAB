# custom cpu design

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

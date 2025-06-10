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

3. prefer massive wires instead of hareware reuse to assign signal like readData_Processed signal
    although it may cause more wires to be instantiated, but it reduces laging

4. aluOp optimization

for riscv:
|aluOP|add|sub|and|or|xor|nor|slt|sltu|
|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
|R/ICAL(func3)|000|000|111|110|100|-|010|011|
|B(func3)|-|00x|-|-|-|-|10x|11x|
|otherType(func3)|xxx|-|-|-|-|-|-|-|
|current ALU|010|110|000|001|100|-|111|011|
|ideal ALU|000|001|111|110|100|101|010|011|
for mips:
|aluOP|add|sub|and|or|xor|nor|slt|sltu|
|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
|R-Cal(func)|001|011|100|101|110|111|010|011|
|I-Cal(op)|001|011|100|101|110|111|010|011|
|REGIMM(op)|-|-|-|-|-|-|xxx|-|
|I-branch(op)|-|10x|-|-|-|-|11x|-|
|otherType(op)|xxx|-|-|-|-|-|-|-|

So there is no universal ALUop for both riscv and mips. This makes sense because they are different archs and
why would there be any universal ALUop?

But this doesn't mean that an ALUop can't work for both of them. since for any encoding, we could always use
truth table to simplify the circuit to make it work efficient enoough that it does not become bottleneck

But I am not using truth table to optimize aluOp, since I am developing the cpu in an incremental way,
and this method is not extendable. It would be reseaonable to simplify circuit using this method at the final state,
when every other critical designs are finished.

5. optimize shifter op

set op to `{func3[2], ~{func3[0] ^ func7[5]}}`
which is:
00 - ll
10 - rl
11 - ra

which is exactly the same as the original one

# icache design

## structure

1 cache (1024 Byte) = 4 ways
1 way   ( 256 Byte) = 8 blocks(aka. Set)
1 block (  32 Byte) = 8 words
1 word  (   4 Byte)

|     tag(24)     | index(3) | offset(5) |

- offset: select word from a block (xxx00, only three bits valid, represent 8 words)
- index:  select block(Set) from a way
- tag:    each block has a tag, indicating the highest 24 bit of its address

## working principle

on receiving an address, interpret it as tag, index and offset
search on index layer, to find any block with the same tag as input tag
if found, return select the word in this block according to offset and return
else, pick a space to read from mem, ...

## evicting algorithm: Least Recently Used (LRU) approximation

use binary tree to approximate a LRU, number in the tree encodes the path to the most recent node(0 right, 1 left)
after each cache access, update LRU of the corresponding set
when evicting, choose the OPPOSITE path to evict

|\\|hit_way0|hit_way1|hit_way2|hit_way3|
|:--:|:--:|:--:|:--:|:--:|
|LRU[2]|0|0|1|1|
|LRU[1]|0|1|-|-|
|LRU[0]|-|-|0|1|

for each set, the LRU(Least Recent Used algorithm) is approximately represented
with a binary tree(three bit signal with order: root node, lchid and rchild),
which represents the path to the recent used way, with 0-left and 1-right.
for example, if LRU[reqIdx] == 3'b101, then it means first right then right, so way3 is most recently used

|LRU[2]|LRU[1]|LRU[0]|evictWay0|evictWay1|evictWay2|evictWay3|
|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
|0|0|0|0|0|0|1|
|0|0|1|0|0|1|0|
|0|1|0|0|0|0|1|
|0|1|1|0|0|1|0|
|1|0|0|0|1|0|0|
|1|0|1|0|1|0|0|
|1|1|0|1|0|0|0|
|1|1|1|1|0|0|0|

# dcache design

## FSM state design

- **WAIT**: set `to_cpu_mem_req_ready` and wait for cpu to send a request
- **TAG_RD**: read the request addr from cpu and see if it's cachable, then check if cache hit

if it is not cachable, enter bypath logic:

- **WRR_BY**: bypath send mem write request. set `to_mem_wr_req_valid`, output `to_mem_wr_req_len == 0`
    and wait for mem to be ready
- **WR_BY**: bypath write data to mem. set `to_mem_wr_data_valid`
    and output correct `to_mem_wr_data`, `to_mem_wr_data_strb`, `to_mem_wr_last == 1`
    then wait for mem to be ready

- **RDR_BY**: bypath send mem read request. set `to_mem_rd_req_valid`, output `to_mem_rd_req_len == 0`
    and wait for mem to be ready
- **RD_BY**: bypath receive data from mem. set `to_mem_rd_rsp_ready`
- **RSP_BY**: bypath respond to cpu. set `to_cpu_cache_rsp_valid` and output data read from mem
    wait for cpu to be ready

else if it is cacheable but not hit, enter evict logic:

- **EVICT**: decide wether to write-back accoding to dirty
- **WRR_MEM**: send mem write request. set `to_mem_wr_req_valid`, output `to_mem_wr_len == 7`
    wait for mem to be ready
- **RDR_MEM**: send mem read request. set `to_mem_rd_req_valid`, output `to_mem_rd_req_len == 7`
    wait for mem to be ready
- **RD_MEM**: receive data from mem. set `to_mem_rd_rsp_ready`
- **REFILL**: refill block to cache.

else cachable and hit, enter normal logic:

- **RD_CCH**: read data from cache. read a block and select data by offset
- **RSP_CCH**: cache respond to cpu. set `to_cpu_cache_rsp_valid` and output data selected in RD_CCH
    wait for cpu to be ready
- **WR_CCH**: write data to cache and **set dirty**

## problems faced

When the program stores data to mem through the bypass, cpu receives read handshake signal and
proceed to execute following instructions. But at this time, dcache may not have stored the data to mem yet.
this may cause errors since cpu would execute following instructions before the sw instrcution is actually finished.

This happens because of **the CPU FSM state design**. ld inst has LD and RDW states seperately for read_req and read_rsp.
whereas st inst has only ST state for both write_req and write_rsp

the solutions: for write request, dcache send req_ready signal only after the data has been actually written to its place (mem or cache)
    for read signals, send ready signal right after WAIT state

# DMA design

## task breakdown

there is a mem_cpy program that copied data from buffer0(in mem) to buffer1.
But coping data using a program is slow, we want to write a hardware to help use do that,
This is the DMA engine.

Buffer0 is devided into sub-buffers(4 kB for each), while working, cpu and DMA maintains a
ringed-queue together:
- cpu writes data to buffer and move `head` forward to the recently filled sub-buffer
- DMA moves data from the sub-buffer pointed by `tail` to buffer1

### How DMA works

DMA works automatically whenever `tail` is lagged behind `head`
when finished moving a sub-buffer, send a intr to notify cpu

for each sub-buffer, DMA breaks it into several burst transmits:
1. send burst read req to mem, with max_len 32Byte
2. store read data to FIFO
3. send burst write req to mem
4. write data from FIFO to mem
5. loop to 1 until sub_buffer is fully moved, then
6. update tail_ptr: tail_ptr += dma_size
7. send intr signal to CPU: set INTR bit in ctrl_stat

this requires (N / 32 + (N % 32 != 0)) times of burst transmits
when N = 4KB, it needs 128 times of burst transmits

- How does DMA where to read from or write to the mem?
    src_base(in 0x0000) stores the read base addr
    dest_base(in 0x0004) stores the write base addr

    thus the addr of sub-buffer to read from(in buffer0) can be calculated with: `src_base + tail_ptr`
    the addr of sub-buffer to write to(in buffer1) can be calculated with: `dest_base + tail_ptr`

### How CPU works

each time in IF state, check if there is and intr
if so, then:
1. save PC to EPC, and jump to intr entrance(0x100), and shield all further intr signal
2. when intr program hits inst `ERET`, recover EPC to PC, relieve intr shield

the intr program is left for us to implement, shoud:
1. reset the INTR bit of ctrl_stat to 0
2. mark copied sub-buffer according to tail_ptr
3. end with an ERET

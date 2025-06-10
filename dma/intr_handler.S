.data
last_tail_ptr:
        .word 0

.globl intr_handler
	.align  2
	.type intr_handler, @function
	.section .exception

intr_handler:
	# TODO: Please add your own interrupt handler for DMA engine 

	# reset INTR bit of ctrl_stat to 0
	la $k0, 0x60020000    # dma_mmio base addr (given in P04)
	lw $k0, 0x14($k0)     # load ctrl_stat to k0, with offset 0x14
	li $k1, 0x7fffffff
	and $k0, $k1, $k0     # set INTR bit to 0
	la $k1, 0x60020000
	sw $k0, 0x14($k1)     # store ctrl_stat back

	# calculate new_tail_ptr - old_tail_ptr
	la $k1, 0x60020000
	lw $k1, 0x8($k1)      # load new_tail_ptr to k1
	la $k0, last_tail_ptr
	lw $k0, 0($k0)        # load last_tail_ptr to k0
	sub $k0, $k1, $k0     # save new - old to k0

	# decrease dma_buf_stat by (new - old) / dma_size
	b $TestCondition
	nop
$Loop:
	lw $k1, 0x10($0)        # load dma_buf_stat to k1
	addi $k1, $k1, -1     # dma_buf_stat--
	sw $k1, 0x10($0)      # save dma_buf_stat back

	la $k1, 0x60020000
	lw $k1, 0x10($k1)     # load dma_size to k1
	sub $k0, $k0, $k1     # subtract dma_size from new - old

$TestCondition:
	bgtz $k0, $Loop
	nop

	# save last_tail_ptr for future use
	la $k0, last_tail_ptr
	la $k1, 0x60020000
	lw $k1, 0x08($k1)
	sw $k1, 0($k0)

	# return with a eret
	eret





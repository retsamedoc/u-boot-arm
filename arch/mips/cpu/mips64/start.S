/*
 *  Startup Code for MIPS64 CPU-core
 *
 *  Copyright (c) 2003	Wolfgang Denk <wd@denx.de>
 *
 * SPDX-License-Identifier:	GPL-2.0+
 */

#include <asm-offsets.h>
#include <config.h>
#include <asm/regdef.h>
#include <asm/mipsregs.h>

#ifndef CONFIG_SYS_MIPS_CACHE_MODE
#define CONFIG_SYS_MIPS_CACHE_MODE CONF_CM_CACHABLE_NONCOHERENT
#endif

#ifndef CONFIG_SYS_INIT_SP_ADDR
#define CONFIG_SYS_INIT_SP_ADDR	(CONFIG_SYS_SDRAM_BASE + \
				CONFIG_SYS_INIT_SP_OFFSET)
#endif

#ifdef CONFIG_SYS_LITTLE_ENDIAN
#define MIPS64_R_INFO(ssym, r_type3, r_type2, r_type) \
	(((r_type) << 24) | ((r_type2) << 16) | ((r_type3) << 8) | (ssym))
#else
#define MIPS64_R_INFO(ssym, r_type3, r_type2, r_type) \
	((r_type) | ((r_type2) << 8) | ((r_type3) << 16) | (ssym) << 24)
#endif

	/*
	 * For the moment disable interrupts, mark the kernel mode and
	 * set ST0_KX so that the CPU does not spit fire when using
	 * 64-bit addresses.
	 */
	.macro	setup_c0_status set clr
	.set	push
	mfc0	t0, CP0_STATUS
	or	t0, ST0_CU0 | \set | 0x1f | \clr
	xor	t0, 0x1f | \clr
	mtc0	t0, CP0_STATUS
	.set	noreorder
	sll	zero, 3				# ehb
	.set	pop
	.endm

	.set noreorder

	.globl _start
	.text
_start:
	/* U-boot entry point */
	b	reset
	 nop

	.org 0x200
	/* TLB refill, 32 bit task */
1:	b	1b
	 nop

	.org 0x280
	/* XTLB refill, 64 bit task */
1:	b	1b
	 nop

	.org 0x300
	/* Cache error exception */
1:	b	1b
	 nop

	.org 0x380
	/* General exception */
1:	b	1b
	 nop

	.org 0x400
	/* Catch interrupt exceptions */
1:	b	1b
	 nop

	.org 0x480
	/* EJTAG debug exception */
1:	b	1b
	 nop

	.align 4
reset:

	/* Clear watch registers */
	dmtc0	zero, CP0_WATCHLO
	dmtc0	zero, CP0_WATCHHI

	/* WP(Watch Pending), SW0/1 should be cleared */
	mtc0	zero, CP0_CAUSE

	setup_c0_status ST0_KX 0

	/* Init Timer */
	mtc0	zero, CP0_COUNT
	mtc0	zero, CP0_COMPARE

#ifndef CONFIG_SKIP_LOWLEVEL_INIT
	/* CONFIG0 register */
	dli	t0, CONF_CM_UNCACHED
	mtc0	t0, CP0_CONFIG
#endif

	/*
	 * Initialize $gp, force 8 byte alignment of bal instruction to forbid
	 * the compiler to put nop's between bal and _gp. This is required to
	 * keep _gp and ra aligned to 8 byte.
	 */
	.align	3
	bal	1f
	 nop
	.dword	_gp
1:
	ld	gp, 0(ra)

#ifndef CONFIG_SKIP_LOWLEVEL_INIT
	/* Initialize any external memory */
	dla	t9, lowlevel_init
	jalr	t9
	 nop

	/* Initialize caches... */
	dla	t9, mips_cache_reset
	jalr	t9
	 nop

	/* ... and enable them */
	dli	t0, CONFIG_SYS_MIPS_CACHE_MODE
	mtc0	t0, CP0_CONFIG
#endif

	/* Set up temporary stack */
	dli	t0, -16
	dli	t1, CONFIG_SYS_INIT_SP_ADDR
	and	sp, t1, t0		# force 16 byte alignment
	dsub	sp, sp, GD_SIZE		# reserve space for gd
	and	sp, sp, t0		# force 16 byte alignment
	move	k0, sp			# save gd pointer
#ifdef CONFIG_SYS_MALLOC_F_LEN
	dli	t2, CONFIG_SYS_MALLOC_F_LEN
	dsub	sp, sp, t2		# reserve space for early malloc
	and	sp, sp, t0		# force 16 byte alignment
#endif
	move	fp, sp

	/* Clear gd */
	move	t0, k0
1:
	sw	zero, 0(t0)
	blt	t0, t1, 1b
	 daddi	t0, 4

#ifdef CONFIG_SYS_MALLOC_F_LEN
	daddu	t0, k0, GD_MALLOC_BASE	# gd->malloc_base offset
	sw	sp, 0(t0)
#endif

	dla	t9, board_init_f
	jr	t9
	 move	ra, zero

/*
 * void relocate_code (addr_sp, gd, addr_moni)
 *
 * This "function" does not return, instead it continues in RAM
 * after relocating the monitor code.
 *
 * a0 = addr_sp
 * a1 = gd
 * a2 = destination address
 */
	.globl	relocate_code
	.ent	relocate_code
relocate_code:
	move	sp, a0			# set new stack pointer
	move	fp, sp

	move	s0, a1			# save gd in s0
	move	s2, a2			# save destination address in s2

	dli	t0, CONFIG_SYS_MONITOR_BASE
	dsub	s1, s2, t0		# s1 <-- relocation offset

	dla	t3, in_ram
	ld	t2, -24(t3)		# t2 <-- __image_copy_end
	move	t1, a2

	dadd	gp, s1			# adjust gp

	/*
	 * t0 = source address
	 * t1 = target address
	 * t2 = source end address
	 */
1:
	lw	t3, 0(t0)
	sw	t3, 0(t1)
	daddu	t0, 4
	blt	t0, t2, 1b
	 daddu	t1, 4

	/* If caches were enabled, we would have to flush them here. */
	dsub	a1, t1, s2		# a1 <-- size
	dla	t9, flush_cache
	jalr	t9
	 move	a0, s2			# a0 <-- destination address

	/* Jump to where we've relocated ourselves */
	daddi	t0, s2, in_ram - _start
	jr	t0
	 nop

	.dword	__rel_dyn_end
	.dword	__rel_dyn_start
	.dword	__image_copy_end
	.dword	_GLOBAL_OFFSET_TABLE_
	.dword	num_got_entries

in_ram:
	/*
	 * Now we want to update GOT.
	 *
	 * GOT[0] is reserved. GOT[1] is also reserved for the dynamic object
	 * generated by GNU ld. Skip these reserved entries from relocation.
	 */
	ld	t3, -8(t0)		# t3 <-- num_got_entries
	ld	t8, -16(t0)		# t8 <-- _GLOBAL_OFFSET_TABLE_
	dadd	t8, s1			# t8 now holds relocated _G_O_T_
	daddi	t8, t8, 16		# skipping first two entries
	dli	t2, 2
1:
	ld	t1, 0(t8)
	beqz	t1, 2f
	 dadd	t1, s1
	sd	t1, 0(t8)
2:
	daddi	t2, 1
	blt	t2, t3, 1b
	 daddi	t8, 8

	/* Update dynamic relocations */
	ld	t1, -32(t0)		# t1 <-- __rel_dyn_start
	ld	t2, -40(t0)		# t2 <-- __rel_dyn_end

	b	2f			# skip first reserved entry
	 daddi	t1, 16

1:
	lw	t8, -4(t1)		# t8 <-- relocation info

	dli	t3, MIPS64_R_INFO(0x00, 0x00, 0x12, 0x03)
	bne	t8, t3, 2f		# skip non R_MIPS_REL32 entries
	 nop

	ld	t3, -16(t1)		# t3 <-- location to fix up in FLASH

	ld	t8, 0(t3)		# t8 <-- original pointer
	dadd	t8, s1			# t8 <-- adjusted pointer

	dadd	t3, s1			# t3 <-- location to fix up in RAM
	sd	t8, 0(t3)

2:
	blt	t1, t2, 1b
	 daddi	t1, 16			# each rel.dyn entry is 16 bytes

	/*
	 * Clear BSS
	 *
	 * GOT is now relocated. Thus __bss_start and __bss_end can be
	 * accessed directly via $gp.
	 */
	dla	t1, __bss_start		# t1 <-- __bss_start
	dla	t2, __bss_end		# t2 <-- __bss_end

1:
	sd	zero, 0(t1)
	blt	t1, t2, 1b
	 daddi	t1, 8

	move	a0, s0			# a0 <-- gd
	move	a1, s2
	dla	t9, board_init_r
	jr	t9
	 move	ra, zero

	.end	relocate_code

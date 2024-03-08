
;--- enter ring0 pm to allow deb386 to run.

	.286
	.model tiny
	.dosseg
	.stack 2048
	.386P            ; 386 instructions + privileged opcodes

CStr macro text:vararg
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
endm

cr equ 13
lf equ 10

	include ..\debugsys.inc

;--- GDT descriptors

code16sel   equ 08h
data16sel   equ 10h
tsssel      equ 18h
code16r3    equ 20h or 3
data16r3    equ 28h or 3
flatsel     equ 30h or 3
code32r3    equ 38h or 3
data32r3    equ 40h or 3

desc struct
limit     dw  ?       ; segment limit
base00_15 dw  ?       ; low word of base address
base16_23 db  ?       ; high byte of base address
          db  ?       ; 93h = std ring 0 read/write segment
attr      db  ?       ; attributes, limit 16-19
base24_31 db  ?
desc ends

gate struct
ofs    dw ?
sel    dw ?
attrib dw ?
ofs32  dw ?
gate ends

IRET32S struct
dwIP	dd ?
dwCS	dd ?
dwFlags dd ?
IRET32S ends

	.data

gdt32 label fword
gdt32lim dw gdt_size-1
gdt32adr dd 0

idt32 label fword
idt32lim dw idt_size-1
idt32adr dd 0

rmidt32 label fword
	dw 3ffh
	dd 0

wData dw 0
pminit  df 0

	.code

gdt_start   label qword
            dw  0,0,0,0
code16dsc   desc <-1,0,0,09ah,  0h,0>  ; 08 16-bit execute/read code, 64K
data16dsc   desc <-1,0,0,092h,  0h,0>  ; 10 16-bit read/write data, 64k
tssdsc      desc <67h,0,0,089h, 0h,0>  ; 18 avail 386 TSS
code16r3dsc desc <-1,0,0,0fah,  0h,0>  ; 20 16-bit execute/read code, r3, 64K
data16r3dsc desc <-1,0,0,0f2h,  0h,0>  ; 28 16-bit read/write data, r3, 64K
flatdsc     desc <-1,0,0,0F2h,0cfh,0>  ; 30 32-bit flat data 4G
code32r3dsc desc <-1,0,0,0fah,0cfh,0>  ; 38 32-bit execute/read code, r3, 4G
data32r3dsc desc <-1,0,0,0f2h,0cfh,0>  ; 40 32-bit read/write data, r3, 4G
kddesc      desc <>
            desc <>
            desc <>
kdsel equ (offset kddesc - offset gdt_start)
gdt_size equ $ - offset gdt_start

gattr   equ  8E00h
gattrr3 equ 0EE00h

idt_start label qword
	gate <offset int00, code16sel, gattr, 0>
	gate <offset int01, code16sel, gattr, 0>
	gate <offset int02, code16sel, gattr, 0>
	gate <offset int03, code16sel, gattr, 0>
	gate <offset int04, code16sel, gattr, 0>
	gate <offset int05, code16sel, gattr, 0>
	gate <offset int06, code16sel, gattr, 0>
	gate <offset int07, code16sel, gattr, 0>
	gate <offset int08, code16sel, gattr, 0>
	gate <offset int09, code16sel, gattr, 0>
	gate <offset int0A, code16sel, gattr, 0>
	gate <offset int0B, code16sel, gattr, 0>
	gate <offset int0C, code16sel, gattr, 0>
	gate <offset int0D, code16sel, gattr, 0>
	gate <offset int0E, code16sel, gattr, 0>
	gate <offset int0F, code16sel, gattr, 0>
	gate <offset int10, code16sel, gattr, 0>
	gate <offset int11, code16sel, gattr, 0>
	gate <offset int12, code16sel, gattrr3, 0>
	gate 2Fh dup (<>)	; kd expects IDT to contain entry for INT 41h!
idt_size equ $ - offset idt_start

tss_start label dword
     dd 0
r0sp dw 0,0
r0ss dd data16sel
	db 5Ch dup (0)

	include vioout.inc
	include printf.inc

@int macro intno,cleansp
int&intno:
ifnb <cleansp>
	add sp, 4
endif
	push intno&h
	jmp err
endm

	@int 00
	@int 01
	@int 02
	@int 03
	@int 04
	@int 05
	@int 06
	@int 07
	@int 08,1
	@int 09
	@int 0A,1
	@int 0B,1
	@int 0C,1
	@int 0D,1
	@int 0E,1
	@int 0F
	@int 10
	@int 11
err:
	pop ax	; exc#
	pop edx	; eip
	pop ecx	; cs
	invoke printf, CStr("exc %X at cs:ip=%X:%lX",lf), ax, cx, edx
	mov sp, r0sp
	jmp backfromr332

;--- int 12h is used here to switch back to ring0

int12:
	add sp, 5*4	; skip return frame
	cmp dl, 0
	jz backfromr316
	cmp dl, 1
	jz backfromr332
	int 3

r3proc16 proc
	mov dl, 0
	int 12h
r3proc16 endp

_TEXT32 segment use32 word public 'CODE'
r3proc32 proc
	mov dl, 1
	int 12h
r3proc32 endp

_TEXT32 ends

;--- protected-mode test proc

dotest proc

;--- prepare running r3 code

	mov r0sp, sp

	mov byte ptr [tssdsc][5], 89h
	mov ax, tsssel
	ltr ax

	pushf
	movzx esp, sp
	and word ptr [esp], 0Bfffh	; reset NT
	popf

	mov ax, flatsel
	mov ds, ax
	mov es, ax

;--- enter kd if installed

	cmp word ptr cs:pminit+4, 0
	jz @F
	int 3
@@:

;--- switch to both 16-bit and 32-bit ring3 code

	mov eax, esp
	push 0
	push data16r3	; ss
	push eax		; esp
	push 0
	push code16r3	; cs
	push 0
	push offset r3proc16 ;ip
	retd
backfromr316::
	mov eax, esp
	push 0
	push data16r3	; ss
	push eax		; esp
	push 0
	push code32r3	; cs
	push 0
	push lowword offset r3proc32 ;ip
	retd
backfromr332::
	ret

dotest endp


enterpm proc

	cli
	lgdt [gdt32]
	lidt [idt32]
	mov eax, cr0
	or al, 1
	mov cr0, eax
	mov ax, data16sel
	mov ss, ax
	mov ds, ax
	mov es, ax
	push code16sel
	push offset @F
	retf
@@:
	xor ax, ax
	lldt ax
	ret
enterpm endp

enterrm proc

	mov ax, data16sel
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax

	mov eax, cr0
	and al, not 1
	mov cr0, eax
	jmp @F
@@:
	mov ax, @data
	mov ss, ax
	mov ds, ax
	mov es, ax
	lidt [rmidt32]
	push ax
	push offset @F
	retf
@@:
	ret

enterrm endp

main proc

	smsw ax
	test al,1
	jnz error
	mov wData, ds

	mov ax, cs
	movzx eax, ax
	shl eax, 4
	add eax, offset gdt_start
	mov [gdt32adr], eax

	mov ax, cs
	movzx eax, ax
	shl eax, 4
	add eax, offset idt_start
	mov [idt32adr], eax

	mov ax, cs
	movzx eax, ax
	shl eax, 4
	add eax, offset tss_start
	mov [tssdsc].base00_15, ax
	shr eax, 16
	mov [tssdsc].base16_23, al

	mov ax, ds
	movzx eax, ax
	shl eax, 4
	mov [code16dsc].base00_15, ax
	mov [data16dsc].base00_15, ax
	mov [code16r3dsc].base00_15, ax
	mov [data16r3dsc].base00_15, ax
	mov [data32r3dsc].base00_15, ax
	shr eax, 16
	mov [code16dsc].base16_23, al
	mov [data16dsc].base16_23, al
	mov [code16r3dsc].base16_23, al
	mov [data16r3dsc].base16_23, al
	mov [data32r3dsc].base16_23, al

	mov ax, _TEXT32
	movzx eax, ax
	shl eax, 4
	mov [code32r3dsc].base00_15, ax
	shr eax, 16
	mov [code32r3dsc].base16_23, al

	mov ah, D386_Identify
	int D386_RM_Int
	cmp ax, D386_Id
	mov dx, CStr("no kernel debugger installed",13,10,'$')
	jnz exit
	mov bx, flatsel   ; flat selector
	mov cx, kdsel
	mov dx, 0	; no GDT sel
	mov si, offset gdt_start	; ds:si=gdt
	mov di, offset idt_start	; es:di=idt
	mov ah, D386_Prepare_PMode
	int D386_RM_Int
	mov dword ptr [pminit+0], edi
	mov  word ptr [pminit+4], es
	push ds
	pop es

	call enterpm

	cmp word ptr [pminit+4],0
	jz @F
	mov edi, offset idt_start	;es:edi=idt
	mov al, PMINIT_INIT_IDT
	call [pminit]
	mov ax, DS_DebLoaded
	int 41h
	cmp ax, DS_DebPresent
	jnz @F
	mov ax, DS_CondBP
	int 41h
@@:
	call dotest
	call enterrm
	sti
	ret
error:
	mov dx, CStr("program runs in true real-mode only",13,10,'$')
exit:
	mov ah,9
	int 21h
	ret

main endp

start:
	mov ax, @data
	mov ds, ax
	mov bx, ss
	sub bx, ax
	shl bx, 4
	mov ss, ax
	add sp, bx
	mov es, ax
	mov bx, sp
	shr bx, 4
	mov ah, 4Ah
	int 21h
	call main
	mov ah, 4ch
	int 21h

	end start

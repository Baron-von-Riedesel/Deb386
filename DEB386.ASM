
;*** Deb386: ring 0 debugger for hdpmi/win3x.
;--- uses Debug/X's DebugR.bin variant.
;--- assembled with JWasm:
;---   jwasm -mz Deb386.asm
;--- if Masm is used, DebugR.bin must be converted to DebugR.inc.
;--- if debug displays are enabled (_DEBUG), JWasm v2.17 is required.

	.286
	.model tiny
	.stack 1024
	.dosseg
	option casemap:none
	option proc:private
	.386

OPT_INST   equ 1
OPT_DEINST equ 2
OPT_NOI41  equ 4
OPT_ALTVID equ 8
OPT_INT3INIT equ 16

ifndef INT4102
INT4102 equ 1	; 1=display debug string displays
endif

cr equ 13
lf equ 10

MEMADD equ 480h	; DebugR needs: 200h stack, 257 line_in buffer, 264 line_out buffer

ifndef VIOOUT
VIOOUT equ 0
endif
ifndef KBDIN
KBDIN  equ 0
endif
ifndef AUXOUT
AUXOUT equ 0
endif
ifndef AUXIN
AUXIN  equ 0
endif

DStr macro text:vararg
local sym
CONST segment word public 'CONST'
sym db text,'$'
CONST ends
	exitm <offset sym>
endm

DGROUP group CONST

ifdef _DEBUG
;--- debug displays might be done on a 32-bit stack
STACK32 segment use32 stack 'STACK'
STACK32 ends
endif

XMSMOVE struct
dwSize dd ?
hSrc   dw ?
dwSrc  dd ?
hDst   dw ?
dwDst  dd ?
XMSMOVE ends

	include debugsys.inc

	.data

oldint68 dd ?
ife (AUXIN or KBDIN)
oldint09 dd ?
endif
oldint41 df ?
wOpt  dw 0

	align

wKDCS dw ?
wKDDS dw ?
wFlat dw ?
wGDT  dw ?
dwCmdL dd ?

dfInit label fword
wOfsInit dw offset startdbg, 0
wSegInit dw ?

dfGetStk label fword
wOfsGetStk dw offset startdbg+3, 0
wSegGetStk dw ?

ife ( AUXOUT or VIOOUT )
dfPutChr df ?
endif
ife ( AUXIN or KBDIN )
dfGetChr df ?
endif

dwXMS   dd ?
wHdl    dw ?
wStart  dw ?
wSize   dw ?
xmsbm   XMSMOVE <>

	.code

startdbg label near
ifdef __JWASM__
%	incbin <BINDIR\debugR.bin>
else
	include debugR.inc	; for Masm, DebugR.bin must be converted to DebugR.inc ( tool bin2inc.exe )
endif
	align 2
sizedbg equ $ - startdbg
	db MEMADD dup (0)
enddbg label near

ifdef _DEBUG
	include dprintfr.inc
	assume ss:STACK32
	option stackbase:ebp
	include dprintfp.inc
else
@dprintfr textequ <;>
@dprintfp textequ <;>
endif

if VIOOUT
	include vioout.inc
elseif AUXOUT
	include auxout.inc
endif
if KBDIN
	include kbdinp.inc
endif

ifdef _DEBUG
	assume ss:DGROUP
	option stackbase:bp
endif

myint68 proc
	cmp ah, D386_Identify
	jz isId
	cmp ah, D386_Prepare_PMode
	jz isPrepPM
ifdef _DEBUG
	cmp ah, D386_Display_Char
	jz is51
endif
	@dprintfr "int 68, ax=%X, unhandled", ax
	jmp cs:[oldint68]
isId:
	@dprintfr "int 68, ax=%X, returning D386_Id", ax
	mov ax, D386_Id
	iret
ifdef _DEBUG
is51:
	push bx
	mov ah,0Eh
	mov bh,0
	int 10h
	pop bx
	iret
endif
isPrepPM:

	@dprintfr "int 68, ax=%X, cx=%X, bx=%X, dx=%X, ds:si=%X:%X, es:di=%X:%X", ax, cx, bx, dx, ds, si, es, di

;--- in:
;--- cx=2 selectors reserved for KD
;--- bx=flat sel
;--- dx=GDT sel
;--- ds:si=GDT
;--- es:si=IDT
;--- out: es:edi=protected-mode function

	pushad

	mov cs:[wKDCS], cx
	mov cs:[wSegInit], cx
	mov cs:[wSegGetStk], cx
	add cx, 8
	mov cs:[wKDDS], cx
	mov cs:[wFlat], bx
	mov cs:[wGDT], dx

;--- init code/data GDT descriptors for DebugR

	mov bx, cs:[wKDCS]
	mov eax, cs
	shl eax, 4
	mov ds:[si+bx+2], ax
	mov ds:[si+bx+2+8], ax
	shr eax, 16
	mov ds:[si+bx+4], al
	mov ds:[si+bx+4+8], al
	mov ds:[si+bx+7], ah
	mov ds:[si+bx+7+8], ah
	mov ax, offset endres
	or al, 0Fh
	mov word ptr ds:[si+bx+0], ax
	mov word ptr ds:[si+bx+0+8], ax
	mov word ptr ds:[si+bx+5], 009Bh
	mov word ptr ds:[si+bx+5+8], 0093h

	push ds

;--- reinit DebugR binary

	push cs
	pop ds
	mov si, offset xmsbm
;	mov [si].XMSMOVE.dwSize, sizedbg
	mov ax, [wHdl]
	mov [si].XMSMOVE.hSrc, ax
	mov [si].XMSMOVE.dwSrc, 0
	mov [si].XMSMOVE.hDst, 0
	mov ax, [wStart]
	mov word ptr [si].XMSMOVE.dwDst+0, ax
	mov word ptr [si].XMSMOVE.dwDst+2, cs
	mov ah, 0Bh
	call [dwXMS]

ife (AUXIN or KBDIN)

;--- get the real-mode int 09 in case we rely
;--- on working kbd driver code in real-mode.

	push 0
	pop ds
	mov eax, ds:[9*4]
	mov cs:[oldint09], eax
endif

	pop ds
	popad
	mov edi, offset pminit
	mov es, cs:[wKDCS]
	iret

myint68 endp

ifdef _DEBUG
	assume ss:STACK32
	option stackbase:ebp
endif

if INT4102

;--- display string ds:esi

dispstr proc
if VIOOUT
	cmp cs:[bAlt],0
	jz @F
	push ds
	mov ds, cs:[wKDDS]
	call SwitchVid	; assumes ds==dgroup!
	pop ds
	call @F
	push ds
	mov ds, cs:[wKDDS]
	call SwitchVid
	pop ds
	ret
@@:
endif
@@:
	lodsb ds:[esi]
	and al, al
	jz @F
if VIOOUT
	call VioPutChar
elseif AUXOUT
	call AuxPutChar
else
	call cs:[dfPutChr]
endif
	jmp @B
@@:
	ret
dispstr endp

endif

myint41 proc
	cmp ax, DS_DebLoaded
	jz is4f
if INT4102
	cmp ax, DS_Out_Str
	jz is02
endif
	cmp ax, DS_CondBP
	jz isf001
	@dprintfp "Int 41, ax=%X, unhandled", ax
if 0
	jmp cs:[oldint41]
else
	iretd
endif
is4f:
	@dprintfp "Int 41, DebLoaded: handled"
	mov ax, DS_DebPresent
	iretd
if INT4102
is02:
	pushad
	call dispstr
	popad
	iretd
endif
isf001:
	test cs:[wOpt], OPT_INT3INIT
	jz @F
	int 3
@@:
	@dprintfp "Int 41, CondBP, handled"
	iretd
myint41 endp

pminit proc far
	cmp al, PMINIT_INIT_IDT
	jz initIDT
	cmp al, PMINIT_INIT_PAGING
	jz initPg
	@dprintfp "pminit: called with ax=%X, unhandled", ax
	retd

initIDT:

;--- called with es:edi=IDT

if (AUXOUT or VIOOUT) eq 0 or (AUXIN or KBDIN) eq 0
;--- if i/o must be thru HDPMI, exit quickly if not called by HDPMI
	cmp dword ptr ds:[0], "MPDH"   
	jz @F
	retd
@@:
endif

	pushad
	push ds
	mov ds, cs:[wKDDS]

;--- HDPMI specific: set i/o vectors supplied by hdpmi

	mov ax, [esp+2+8*4+4]	; get callers CS
ife (AUXOUT or VIOOUT)
	mov dword ptr [dfPutChr+0], ebx
	mov word ptr [dfPutChr+4], ax
endif
ife (AUXIN or KBDIN)
	mov dword ptr [dfGetChr], edx
	mov word ptr [dfGetChr+4], ax
endif

;--- install int 41h handler

	test [wOpt], OPT_NOI41
	jnz @F
	push edi
	lea edi, [edi+8*41h]
	mov ax, es:[edi+6]
	shl eax, 16
	mov ax, es:[edi+0]
	mov dx, es:[edi+2]
	mov dword ptr [oldint41+0], eax
	mov word ptr [oldint41+4], dx
	mov es:[edi+0], offset myint41
	mov es:[edi+2], cs
	mov word ptr es:[edi+4], 0EE00h	; 386 interrupt gate, DPL=3
	mov word ptr es:[edi+6], 0
	pop edi
@@:
	pop ds

	@dprintfp "pminit, initIDT: es:edi=%X:%lX, calling DebugR.Init", es, edi

;--- debugger expects:
;--- ax = data selector, hiword: scratch selector
;--- bp = size data
;--- cx = flat selector
;--- ebx = offset vio
;--- edx = offset kbd
;--- esi = linear address cmdline
;--- es:edi=IDT

	mov esi, cs:[dwCmdL]
	mov ax, cs:[wKDDS]
	push ax
	add ax, 8
	shl eax, 16
	pop ax
	mov bp, offset enddbg
	mov cx, cs:[wFlat]
	mov ebx, offset vioproc
	mov edx, offset kbdproc
	call cs:[dfInit]

	@dprintfp "pminit, initIDT: DebugR initialized"

	popad
	retd

initPg:
;--- bx=phys-linear selector
	retd
pminit endp

;--- DebugR callout
;--- entry:
;--- ss=dgroup
;--- ds=currently always dgroup, but may change

vioproc proc far
	cmp ah, 0Eh
	jz is0E
	cmp ah, 03h
	jz is03
	cmp ah, 05h		; if DebugR's "page flipping" feature is on
	jz is05
	retd
is0E:
if VIOOUT
	cmp cs:[bAlt],0
	jz isStd
	call SwitchVid	; assumes ds==dgroup!
 ifdef _DEBUG
	movzx esp, sp
 endif
	call VioPutChar
	call SwitchVid
	retd
isStd:
	call VioPutChar
elseif AUXOUT
	call AuxPutChar
else
	pusha
	mov cl, al
	call cs:[dfGetStk]	; get current ring0 stack
	mov bp, sp
	mov di, ss
	mov ss, dx
	mov esp, eax
	mov al, cl
	call cs:[dfPutChr]
	mov ss, di
	mov sp, bp
	popa
endif
	retd
is03:		; get cursor pos
if AUXOUT
	call AuxGetCsrPos
else
	push ds
	push bx
	mov ds, cs:[wFlat]
	movzx bx, bh
	shl bx, 1
	mov dx, ds:[bx+450h]
	pop bx
	pop ds
endif
	retd
is05:		; set vio page
ife AUXOUT
	pusha
	push ds
	mov ds, cs:[wFlat]
	mov cx, ds:[44Ch]	; page size
	mov ds:[462h], al
	mov ah, 0
	mul cx
	mov ds:[44Eh], ax
	shr ax, 1
	mov dx, ds:[463h]
	mov cl, al
	mov al, 0Ch
	out dx, ax
	mov ah, cl
	inc al
	out dx, ax
	pop ds
	popa
endif
	retd
vioproc endp

;--- call int 16h

kbdproc proc far
if AUXIN
	call AuxGetChar
elseif KBDIN
	call KbdGetChar
else
	pusha
	mov cl, al
	call cs:[dfGetStk]
	mov bp, sp
	mov ss, dx
	mov esp, eax
if 1	; to play it safe, reset int 09
	push ds
	mov ds, cs:[wFlat]
	mov eax, cs:[oldint09]
	push dword ptr ds:[9*4]
	mov ds:[9*4], eax
endif
	call cs:[dfGetChr]
if 1
	pop dword ptr ds:[9*4]
	pop ds
endif
	mov ss, cs:[wKDDS]
	movzx esp, bp
	mov [bp+7*2], ax
	popa
endif
	retd
kbdproc endp

ifdef _DEBUG
	assume ss:DGROUP
	option stackbase:bp
endif

	.data

endres label byte

;--- segments _ITEXT and CONST won't become resident

_ITEXT segment word public 'DATA'

DGROUP group _ITEXT

;--- check cmdline options

handle_options proc

	xor di, di
	xor dx, dx
nextarg:
	mov si, [bx]
	add bx, 2
	cmp si, 0
	jz doneargs
	lodsb
	cmp al, '-'
	jz @F
	cmp al, '/'
	jnz error
@@:
	push offset nextarg
	lodsw		; get the option in AL

	or al, 20h
	cmp ax, 'i'
	jnz noti
	or di, OPT_INST
	mov dx, [bx]
	and dx, dx
	jz @F
	add bx, 2
@@:
	retn
noti:
	cmp ax, 'u'
	jnz @F
	or di, OPT_DEINST
	retn
@@:
	cmp ax,'n'
	jnz @F
	or di, OPT_NOI41
	retn
@@:
	cmp ax,'b'
	jnz @F
	or di, OPT_INT3INIT
	retn
@@:
if VIOOUT
	cmp ax,'2'
	jnz @F
	or di, OPT_ALTVID
	retn
@@:
endif
if AUXIN or AUXOUT
	cmp ax,':c'
	jnz @F
	lodsw
	cmp ax, '1'
	jb @F
	cmp ax, '4'
	ja @F
	sub al, '1'
	mov [wPort], ax
	retn
@@:
endif

;--- handle further options here

	pop ax
error:
	stc
	ret

doneargs:
	clc
	ret
handle_options endp

main proc c argc:word, argv:ptr

	mov ah, 51h
	int 21h
	mov es, bx

	mov bx, argv
	add bx, 2
	call handle_options
	jc disphelp	; invalid cmdline arg
	test di, OPT_INST
	jnz install
	test di, OPT_DEINST
	jnz uninstall
	jmp disphelp

install:
	mov [wOpt], di
	mov di, 81h
	and dx, dx
	jz noargs
	mov si, dx
@@:
	lodsb
	stosb
	and al, al
	jnz @B
	dec di
noargs:
	mov byte ptr es:[di],13
	mov eax, es
	shl eax, 4
	add eax, 81h
	mov [dwCmdL], eax

if VIOOUT
	test [wOpt], OPT_ALTVID
	jz @F
;--- check if second video adapter installed
	mov ax, 1A00h
	int 10h
	cmp al, 1Ah
	jnz @F
	and bh, bh
	jz @F
	mov [bAlt], bh
	call InitVid
@@:
endif

	push 0
	pop es
	cmp dword ptr  es:[68h*4], 0
	jz @F
	mov ah, D386_Identify
	int 68h
	cmp ax, D386_Id
	mov dx, DStr("Deb386 already installed",13,10)
	jz printandexit
@@:

;--- scan DebugR for start of _ITEXT
	mov di, offset startdbg
	mov cx, offset sizedbg
	shr cx, 2
	mov eax, 0DEADBEEFh
	push ds
	pop es
	repnz scasd
	shl cx, 2
	mov [wSize], cx
	mov [wStart], di


;--- get XMS block to save/restore DebugR.bin binary
	mov ax, 4300h
	int 2Fh
	cmp al, 80h
	mov dx, DStr("no XMM found",13,10)
	jnz printandexit
	mov ax, 4310h
	int 2Fh
	mov word ptr [dwXMS+0], bx
	mov word ptr [dwXMS+2], es
	mov ah, 9

	mov dx, wSize
	add dx, 1024-1
	shr dx, 10

	call [dwXMS]
	mov [wHdl], dx
	mov dx, DStr("no XMS memory",13,10)
	cmp ax,0
	jz printandexit
	mov dx, [wHdl]
	mov si, offset xmsbm
	movzx eax, wSize
	mov [si].XMSMOVE.dwSize, eax
	mov [si].XMSMOVE.hSrc, 0
	mov word ptr [si].XMSMOVE.dwSrc+0, di
	mov word ptr [si].XMSMOVE.dwSrc+2, ds
	mov [si].XMSMOVE.hDst, dx
	mov [si].XMSMOVE.dwDst, 0
	mov ah, 0Bh
	call [dwXMS]
	mov dx, DStr("XMS block move failed",13,10)
	cmp ax, 0
	jz printandexit

;--- hook Int 68h

	push 0
	pop es
	mov ax, cs
	shl eax, 16
	mov ax, offset myint68
	xchg eax, es:[68h*4]
	mov [oldint68], eax

	mov dx, DStr("Deb386 installed",13,10)
	call printstring

;--- go resident

	mov ax, cs
	sub ax, 10h
	mov es, ax
	xor ax, ax
	xchg ax, es:[2Ch]
	mov es, ax
	mov ah, 49h
	int 21h

	mov dx, offset endres + 15
	shr dx, 4
	add dx, 10h
	mov ax, 3100h
	int 21h

;--- just remove the installed TSR from memory and free the
;--- XMS handle. There's no possibility to talk to the debugger core
;--- in protected-mode and tell it to "deinstall".

uninstall:
	mov dx, DStr("No installed Deb386 found",13,10)
	push 0
	pop es
	cmp dword ptr  es:[68h*4], 0
	jz printandexit
	mov ah, D386_Identify
	int 68h
	cmp ax, D386_Id
	jnz printandexit

	mov dx, DStr("Can't uninstall",13,10)
	mov eax, es:[68h*4]
	cmp ax, offset myint68
	jnz printandexit
	shr eax, 16
	mov ds, ax
	mov dx, cs
	sub dx, 10h
	mov ecx, [oldint68]
	mov es:[68h*4], ecx
	sub ax, 10h+1
	mov es, ax
	mov es:[1], dx
	mov dx, [wHdl]
	mov ah, 0Ah
	call [dwXMS]
	push cs
	pop ds
	mov dx, DStr("Deb386 uninstalled",13,10)
	jmp printandexit

CONST segment
helpmsg label byte
	db "Deb386 v1.0, ring 0 debugger",13,10
	db "usage: Deb386 [options]",13,10
	db " options:",13,10
if VIOOUT
	db "  -2              use alternate video",13,10
endif
	db "  -b              stop at init",13,10
if AUXIN or AUXOUT
	db "  -c:[1|2|3|4]    set COM port",13,10
endif
	db "  -i [argument]   install",13,10
	db "  -n              invisible to Int 41h",13,10
	db "  -u              uninstall",13,10
	db "  The argument behind the -i option is passed to DebugR.",13,10
	db "  It must be enclosed in quotes if it contains spaces.",13,10
	db '$'
CONST ends

disphelp:
	mov dx, offset helpmsg
printandexit:
	call printstring
	ret
printstring:
	mov ah,9
	int 21h
	retn

main endp

	include setargv.inc

;--- setup tiny model, release DOS memory, call main()

start:
	mov ax, @data
	mov ds, ax
	mov bx, ss
	sub bx, ax
	shl bx, 4
	mov ss, ax
	add sp, bx
	mov bx, sp
	shr bx, 4
	add bx, 10h
	mov ah, 4Ah
	int 21h
	call _setargv
	invoke main, [_argc], [_argv]
	mov ah,4Ch
	int 21h

_ITEXT ends

	END start

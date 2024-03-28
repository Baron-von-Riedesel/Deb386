
;--- Deb386: ring 0 debugger for hdpmi/jemm/win3x/win9x.
;--- uses Debug/X's DebugR.bin variant.
;--- to be assembled with JWasm:
;---   jwasm -mz Deb386.asm
;--- if debug displays are enabled (_DEBUG), JWasm v2.17 is required.
;--- if Masm is used, DebugR.bin must be converted to DebugR.inc, and
;--- debug displays cannot be enabled.
;--- best viewed with TAB size 4.

ifndef DRIVER
DRIVER  equ 0	; 1=creating device driver variant
endif

if DRIVER
;--- in the driver variant, there's a small "prefix" segment (_TEXTD) that
;--- contains the driver peculiarities. Must be defined BEFORE .model so
;--- it's the very first code segment.
_TEXTD segment para public 'CODE'
_TEXTD ends
endif

	.286
	.model tiny
	.stack 1024
	.dosseg
	option casemap:none
	option proc:private
	.386

VERSION textequ <1.3>

ifndef VIOOUT
VIOOUT equ 0	; 1=screen output
endif
ifndef KBDIN
KBDIN  equ 0	; 1=kbd input
endif
ifndef AUXOUT
AUXOUT equ 0	; 1=serial output
endif
ifndef AUXIN
AUXIN  equ 0	; 1=serial input
endif
ifndef INT4100
INT4100 equ 1	; 1=support int 41h, ax=0 - display chars
endif
ifndef INT4102
INT4102 equ 0	; 1=support int 41h, ax=2 - display strings
endif
NOXMS   equ 1	; 1=don't use XMS to save DebugR init code, instead read the binary

OPT_INST     equ 1
OPT_DEINST   equ 2
OPT_NOI41    equ 4
OPT_ALTVID   equ 8
OPT_INT3INIT equ 16
OPT_HDPMI    equ 64

cr equ 13
lf equ 10

MEMADD equ 480h	; DebugR needs: 200h stack, 257 line_in buffer, 264 line_out buffer

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

ife NOXMS
XMSMOVE struct
dwSize dd ?
hSrc   dw ?
dwSrc  dd ?
hDst   dw ?
dwDst  dd ?
XMSMOVE ends
endif

	include debugsys.inc

	.data

oldint68 dd ?
if KBDIN
oldint09 dd ?
endif
oldint41 df ?
wOpt  dw 0

	align

wKDCS dw ?
wKDDS dw ?
wFlat dw ?
;wGDT  dw ?
dwCmdL dd ?

dfInit label fword
         dw offset startdbg, 0
wSegInit dw ?

dfGetStk label fword
           dw offset startdbg+3, 0
wSegGetStk dw ?

if VIOOUT
dfPutChr df ?
endif
if KBDIN
dfGetChr df ?
endif

ife DRIVER
wStart  dw ?	; start offset of DebugR init code
wSize   dw ?	; size of DebugR init code
wHdl    dw ?	; file/XMS handle
endif
if DRIVER
emptycl db 13
else
 if NOXMS
wMyPSP  dw ?	; PSP of Deb386
wHdrSiz dw ?	; size of MZ hdr in bytes
 else
dwXMS   dd ?   
xmsbm   XMSMOVE <>
 endif
endif

if DRIVER
_TEXTD segment
starttextd:
	dw 0ffffh
	dw 0ffffh
	dw 8000h
	dw offset devstrat	; device strategy
	dw offset devint	; device interrupt
;	db '$debugDD'
	db '$Deb386$'

io struct
cmdlen  db ?       ;+ 0:laenge der struktur
        db ?       ;+ 1:
cmd     db ?       ;+ 2
status  dw ?       ;+ 3
        db 8 dup (?); reserved
        db ?       ;+ 0d
dwSize  dd ?       ;+ 0e  init:return last byte
cmdl    dd ?       ;+ 12  init:line
io ends

pIo dw 0,0

devstrat:
	mov cs:[pIo+0],bx
	mov cs:[pIo+2],es
	retf
devint:
	pusha
	push ds
	lds bx, dword ptr cs:[pIo]
	mov [bx].io.status, 8103h
	cmp [bx].io.cmd, 00
@patch:
	jnz donedrv
	call initdrv
donedrv:
	pop ds
	popa
	retf
	align 16	; make sure _TEXT starts at a paragraph
SIZETEXTD equ $ - starttextd
_TEXTD ends
endif

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

if AUXOUT or AUXIN
	include auxout.inc
endif
if VIOOUT
	include vioout.inc
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
	cmp ah, D386_Real_Mode_Init	; back in real-mode, get ready for reinit pmode
	jz isRMInit
ifdef _DEBUG
	cmp ah, D386_Display_Char
	jz is51
endif
	@dprintfr "int 68, ax=%X, unhandled", ax
	jmp cs:[oldint68]
isId:
	cmp cs:[wKDCS],0	; active PM client?
	jnz _iret
	@dprintfr "int 68, ax=%X, returning D386_Id", ax
	mov ax, D386_Id
_iret:
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
isRMInit:
	mov cs:[wKDCS],0	; ready for another client
	iret
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
;	mov cs:[wGDT], dx

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

ife DRIVER

;--- reinit DebugR binary

	push cs
	pop ds
if NOXMS
	mov ah, 51h
	int 21h
	push bx
	mov bx, [wMyPSP]
	mov ah, 50h
	int 21h
	mov bx, [wHdl]
	mov dx, [wStart]
	push dx
	add dx, [wHdrSiz]
	xor cx, cx
	mov ax, 4200h
	int 21h
	pop dx
	add dx, offset startdbg
	mov cx, [wSize]
	mov ah, 3fh
	int 21h
	pop bx
	mov ah, 50h
	int 21h
else
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
endif

endif

if KBDIN

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
else
	call AuxPutChar
endif
	jmp @B
@@:
	ret
dispstr endp

endif

myint41 proc
	cmp ax, DS_DebLoaded
	jz is4f
if INT4100
	cmp ax, DS_Out_Char
	jz is00
endif
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
if INT4100
is00:
	push eax
	mov al, dl
if VIOOUT
	call VioPutChar
else
	call AuxPutChar
endif
	pop eax
	iretd
endif
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

	pushad
	push ds
	mov ds, cs:[wKDDS]

if  (VIOOUT or KBDIN)
	xor ax, ax
	mov word ptr [dfPutChr+4], ax
	mov word ptr [dfGetChr+4], ax
	test [wOpt], OPT_HDPMI			; use i/o vectors supplied by hdpmi?
	jz @F
	cmp dword ptr ss:[0], "MPDH"	; check caller, must be HDPMI
	jnz @F
	mov ax, [esp+2+8*4+4]	; get callers CS
 if VIOOUT
	mov dword ptr [dfPutChr+0], ebx
	mov word ptr [dfPutChr+4], ax
 endif
 if KBDIN
	mov dword ptr [dfGetChr], edx
	mov word ptr [dfGetChr+4], ax
 endif
@@:
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
	cmp word ptr cs:[dfPutChr+4],0
	jnz @F
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
	retd
@@:
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
else
	call AuxPutChar
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
	retd
else
	cmp word ptr cs:[dfGetChr+4], 0
	jnz @F
	call KbdGetChar
	retd
@@:
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
	retd
endif
kbdproc endp

ifdef _DEBUG
	assume ss:DGROUP
	option stackbase:bp
endif

	.data

endres label byte

;--- segments _ITEXT and CONST won't become resident

_ITEXT segment word public 'DATA'	; must not be 'CODE'

DGROUP group _ITEXT

;--- check cmdline options
;--- out: di=options, dx=optional -i argument

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
	jnz notis
	or di, OPT_INST
	retn
notis:
	cmp ax, ':i'
	jnz noti
	cmp byte ptr [si], 0
	jz erropt
	or di, OPT_INST
	mov dx, si
	retn
noti:
ife DRIVER
	cmp ax, 'u'
	jnz @F
	or di, OPT_DEINST
	retn
@@:
endif
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
	cmp ax,"h"
	jnz @F
	or di, OPT_HDPMI
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
erropt:
	pop ax
error:
	stc
	ret

doneargs:
	clc
	ret
handle_options endp

;--- main: install, uninstall, print help

main proc c argc:word, argv:ptr

ife DRIVER
	mov ah, 51h
	int 21h
	mov es, bx
 if NOXMS
	mov [wMyPSP], es
 endif
endif
	mov bx, argv
	add bx, 2
	call handle_options
	jc disphelp	; invalid cmdline arg
	mov ax, di
ife DRIVER
	cmp ax, OPT_DEINST	; -u allows no other options
	jz uninstall
	test al, OPT_DEINST
	jnz disphelp
endif
	test al, OPT_INST
	jz disphelp

;--- install

if DRIVER
	mov eax, ds
	shl eax, 4
	add eax, offset emptycl
	mov [dwCmdL], eax
endif

	mov [wOpt], di
ife DRIVER
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
endif

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
	mov eax, es:[68h*4]
	and eax, eax
	jz @F
	mov dx, DStr("Kernel debugger already installed",13,10)
	cmp ax, offset myint68
	jz printandexit
	mov ah, D386_Identify
	int 68h
	cmp ax, D386_Id
	jz printandexit
@@:

ife DRIVER

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

ife NOXMS
;--- get XMS block to save/restore DebugR's init code part
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
else
;--- get path of Deb386 and open it
	mov es, [wMyPSP]
	mov es, es:[002Ch]
	xor di, di
	mov al, 0
	or cx, -1
@@:
	repnz scasb
	cmp byte ptr es:[di], 0
	jnz @B
	add di, 3
	push ds
	push es
	pop ds
	mov dx, di
	mov ax, 3D00h
	int 21h
	pop ds
	mov dx, DStr("cannot open Deb386 binary",13,10)
	jc printandexit
	mov [wHdl], ax
	mov bx, ax
	sub sp, 10
	mov dx, sp
	mov cx, 10
	mov ah, 3Fh
	int 21h
	add sp, 8
	pop ax
	shl ax, 4
	mov [wHdrSiz], ax
endif
endif

noreinit:

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

if DRIVER
	ret
else

;--- close std files 0-4
	mov cx, 5
	xor bx, bx
@@:
	mov ah, 3Eh
	int 21h
	inc bx
	loop @B

;--- free environment
	mov cx, 5
	xor bx, bx
@@:
	mov ah, 3Eh
	int 21h
	inc bx
	loop @B

	mov ax, cs
	sub ax, 10h
	mov es, ax
	xor ax, ax
	xchg ax, es:[2Ch]
	mov es, ax
	mov ah, 49h
	int 21h

;--- go resident
	mov dx, offset endres + 15
	shr dx, 4
	add dx, 10h
	mov ax, 3100h
	int 21h

uninstall:

;--- just remove the installed TSR from memory;
;--- free the XMS handle/close the file.
;--- There's no possibility to talk to DebugR
;--- in protected-mode and tell it to "deinstall".

	mov dx, DStr("No installed Deb386 found",13,10)
	push 0
	pop es
	mov eax, es:[68h*4]
	cmp ax, offset myint68
	jnz printandexit

;--- useless to call int 68h, the installed instance
;--- might not reply if option -s is active.
;	mov ah, D386_Identify
;	int 68h
;	cmp ax, D386_Id
;	jnz printandexit

	shr eax, 16
	mov fs, ax		; fs = installed instance

	mov ecx, fs:[0]
	cmp ecx, cs:[0]
	jnz printandexit

	cmp fs:[wKDCS], 0
	mov dx, DStr("Deb386 is busy",13,10)
	jnz printandexit

;--- restore int 68h
	mov dx, cs
	sub dx, 10h
	mov ecx, fs:[oldint68]
	mov es:[68h*4], ecx

;--- set MCB owner to our PSP
	sub ax, 10h+1
	mov es, ax
	mov es:[1], dx

;--- free XMS/file handle
ife NOXMS
	mov dx, fs:[wHdl]
	mov ah, 0Ah
	call fs:[dwXMS]
else
	mov ah, 51h
	int 21h
	push bx
	mov bx, fs:[wMyPSP]
	mov ah, 50h
	int 21h
	mov bx, fs:[wHdl]
	mov ah, 3Eh
	int 21h
	pop bx
	mov ah, 50h
	int 21h
endif

noxmsfh:
	mov dx, DStr("Deb386 uninstalled",13,10)
	jmp printandexit

endif

CONST segment
helpmsg label byte
	db "Deb386 v",@CatStr(!",%VERSION,!")," - ring 0 debugger",13,10
	db "usage: Deb386 [options]",13,10
	db " options:",13,10
if VIOOUT
	db "  -2",9,9,"use alternate video",13,10
endif
	db "  -b",9,9,"stop at init",13,10
if AUXIN or AUXOUT
	db "  -c:[1|2|3|4]",9,"set COM port",13,10
endif
if VIOOUT
	db "  -h",9,9,"use HDPMI for I/O",13,10
endif
	db "  -i[:argument]",9,"install",13,10
	db "  -n",9,9,"invisible to Int 41h",13,10
ife DRIVER
	db "  -u",9,9,"uninstall",13,10
endif
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

if DRIVER

;--- driver init
;--- ds:bx=io

initdrv proc far uses es
	mov bp, sp
	mov es, [bp+4]
	assume es:_TEXTD
	mov byte ptr es:[@patch], 0ebh
	mov [bx].io.status, 0100h
	mov word ptr [bx].io.dwSize+0, offset endres + SIZETEXTD
	mov word ptr [bx].io.dwSize+2, es
	mov ax, sp
	mov dx, ss
	push cs
	pop ss
	mov sp,  offset start + 200h
	push dx
	push ax

	les si, [bx].io.cmdl
@@:
	lodsb es:[si]
	and al, al
	jz @F
	cmp al, ' '
	ja @B
@@:
	push ss
	pop ds
	call _setargv
	invoke main, [_argc], [_argv]
	lss sp, dword ptr ds:[start+200h-4]
	ret
initdrv endp

	align 2
start:
	mov ah, 4Ch
	int 21h

else

;--- setup tiny model, release DOS memory, call main()

start:
if 0
	mov ax, @data
else
	mov ax, ds	; for the tiny model, avoid segment relocs
	add ax, 10h
endif
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
	mov si, 81h
	call _setargv
	invoke main, [_argc], [_argv]
	mov ah,4Ch
	int 21h

endif

_ITEXT ends


	END start

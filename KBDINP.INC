
;--- poll keyboard ( US/GE key layout )

ifndef KEYS
KEYS textequ <KBD_US>
endif

;*** keyboard BIOS variables

KBDSTAT  equ   417h
BUFSTA	 equ   41Ah
BUFEND	 equ   41Ch
EBUFSTA  equ   480h
EBUFEND  equ   482h

	.data

lastk db 0

%	include KEYS.inc

cntlkeystab label byte
	db 36h		;R-SH		;codes ctrl keys
	db 2Ah		;L-SH		;order matches bits in 0040h:0017h
	db 1Dh		;CTRL
	db 38h		;ALT
	db 46h		;SCROLL lock;10
	db 45h		;NUM lock	;20
	db 3Ah		;CAPS		;40
	db 52h		;INS		;80
LCTLKEYS equ $ - offset cntlkeystab

	.CODE

;*** get kbd state
;*** ZERO? if no key available

GetKbdStatus proc
	pushf
	pop ax
	test ah, 2			; IF set?
	jz @F
	in al, 21h
	test al, 2			; IRQ 1 enabled?
	jnz @F
	mov al, 0Bh
	out 20h, al
	in al, 20h
	test al, 03h		; irq 0 or irq 1 request?
	jz nopoll
@@:
	in al, 64h
	test al, 01h		; input buffer full?
	jz nokey
	mov ah, al
	in al, 60h
	test ah, 20h		; is it input from PS/2?
	jnz nokey
	call setkbdbiosvars	; set kbd BIOS variables
	mov [lastk], al
	jc nokey
	cmp al,80h
	jnc nokey
	ret
nokey:
	xor al,al
	ret
nopoll:
	push ax
	push ds
	mov ds, cs:[wFlat]
	mov ax,ds:[BUFSTA]	; char in buffer?
	cmp ax,ds:[BUFEND]
	pop ds
	pop ax
	ret

GetKbdStatus endp

;--- set kbd status bios variable
;--- used only if interrupts disabled

setkbdbiosvars proc
	pusha
	push ds
	push es
	mov es, cs:[wKDDS]
	mov ds, cs:[wFlat]
	mov bh,al 				;check if ctrl, shift, alt, ...
	and al,7fh
	mov di,offset cntlkeystab
	mov bl,00
	mov cx, LCTLKEYS
	repnz scasb
	jnz nostd
	mov bl,80h
	shr bl,cl
	mov ch,bh
;	and byte ptr ds:[KBDSTAT+1],not 4 ;reset Sys-Req
	mov ax, ds:[KBDSTAT]
	and ah, not 4			; reset sys-req
	test ch, 80h			; key released or pressed?
	jz @F
	xor bl,0FFh
	and al,bl				; reset flag
	and ah,bl
	jmp setflags
@@:
	or al,bl				; set flag
	or ah,bl				; set flag
setflags:        
	cmp cl,4				; RSHIFT,LSHIFT,CTRL,ALT?
	jnb @F
	mov ds:[KBDSTAT+1],ah
	xor ds:[KBDSTAT],ah
	jmp donestat
@@:
	mov ds:[KBDSTAT],al
donestat:
	and ch,7Fh
	cmp ch,38h				;Alt key?
	jnz @F
	cmp cs:[lastk],0E0h		;last key 0E0? 
	jnz @F
	and byte ptr ds:[496h],not 8	;AltGr
	and ah,08
	or ds:[496h],ah
@@:  
	cmp ch,52h				;INSERT IS a key!
	jz nostd
	pop es
	pop ds
	popa
	stc
	RET
nostd:
	pop es
	pop ds
	popa
	clc
	ret
setkbdbiosvars endp

; *** get char from KBD without wait

GetKbdChar proc
	call GetKbdStatus
	jz nokey
	mov al,[lastk]
	test al,80h
	jnz nokey			;key released, no further processing
	cmp al,39h			;space?
	jz isspace
	cmp al,56h
	ja getkbdxchar
	jb @F
	mov al,36h			; 56 -> 36
@@:
	cmp al,36h
	ja getkbdxchar
	push ds
	mov ds, cs:[wFlat]
	mov bx, offset normalk
	mov ah, ds:[KBDSTAT]
	test ah,3			;shift pressed
	jz @F
	mov bx, offset shiftk
@@:
	test ah,4			;ctrl pressed?
	jz @F
	mov bx, offset ctrlk
@@:
	test ah,8			;alt pressed?
	jz @F
	test byte ptr ds:[496h],8	;AltGr pressed?
	jz getkbdxchar2
	mov bx, offset altgrk
@@:
	pop ds
	movzx ax,al
	add bx, ax
	mov bl,byte ptr [bx]
	and bl,bl
	jz getkbdxchar
	mov al,bl
	ret
isspace:
	mov ah,al
	mov al,' '
	ret
getkbdxchar2:
	pop ds
getkbdxchar:
	mov ah,al
	mov al,00
	ret

nokey:
	xor ax,ax
	ret
GetKbdChar endp

;--- loop to wait for a char

KbdGetChar proc uses bx

@@:
	call GetKbdChar
	and ax,ax
	jz @B
	ret

KbdGetChar endp


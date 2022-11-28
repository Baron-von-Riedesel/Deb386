
;--- protected-mode code for vio output

bs equ 8	; backspace

@getcursorpos macro
	movzx ebx, byte ptr ds:[462h];page
	mov bx, ds:[EBX*2+450h]
endm

@setcursorpos macro
	movzx ebx, byte ptr ds:[462h];page
	mov ds:[EBX*2+450h], ax
endm

;--- print a char
;--- no registers modified

VioPutChar proc

local	wCols:word
local	bChar:byte
local	bRows:byte

	push ds
	pushad

	mov bChar, al
	mov ds, cs:[wFlat]
	mov ch, ds:[0484h]			; rows-1
	mov cl, ds:[044Ah]			; cols
	mov bRows, ch
	@getcursorpos				; bh=row, bl=col
	mov al, bh		;row pos
	mov ch, 0
	mov wCols, cx
	mul cl
	add ax, ax
	mov bh, 00  ; bx=col pos
	add bx, bx
	add bx, ax
	mov si, ds:[044Eh]			; page offset
	cmp word ptr ds:[0463H],3B4h
	jz @F
	add si, 8000h
@@:
	movzx esi, si
	add esi, 0B0000h

	mov al, bChar

	cmp al, cr
	jnz @F
	mov ax, bx
	shr ax, 1
	div cl
	mov al, ah
	xor ah, ah
	add ax, ax
	sub bx, ax
	jmp char_done
@@:
	cmp al, lf
	jnz @F
	add bx, cx
	add bx, cx
	jmp char_done
@@:
	cmp al, bs
	jnz @F
	sub bx, 2
	jmp char_done
@@:
	movzx ebx, bx
	mov ds:[ebx+esi], al
	inc bx
	inc bx
char_done:
	mov al, bRows
	inc al
	mul cl
	add ax, ax
	cmp bx, ax
	jc @F
	call scrollup
	mov bx, ax
@@:
	mov ax, bx
	push ax
	mov cx, wCols
	shr ax, 1
	div cl
	xchg al, ah
	@setcursorpos
	pop ax
	call cursorset
;	call slowdown
	popad
	pop ds
	ret

if 0
slowdown:
	mov cx, 200
@@:
	in al, 61h
	and al, 10h
	cmp al, ah
	mov ah, al
	jz @B
	loop @B
	retn
endif

cursorset:
	add ax, ds:[044EH]	;offset page
	mov dx, ds:[0463H]
	shr ax, 1			;the CRT offset is one plane only, no attribute bytes 
	mov cl, al			;first high byte
	mov al, 0eh
	out dx, ax
	mov ah, cl			;then low byte
	mov al, 0fh
	out dx, ax
	retn

scrollup:			;scroll up one line
	push es
	push ds
	pop es
	mov edi, esi
	push di
	movzx esi, wCols
	lea esi, [esi*2+edi]
	mov cl, byte ptr wCols
	mov al, bRows
	mul cl
	movzx ecx, ax
	shr cx,1
	rep movsd es:[edi], ds:[esi]
	push di
	mov cx, wCols
	mov eax,07200720h
	shr cx, 1
	rep stosd es:[edi]
	pop ax
	pop di
	sub ax, di
	pop es
	retn

VioPutChar endp

	.data

oldcrtp dw 0
oldcsrpos dw 0
oldcols dw 80
oldmr label word
oldmode   db 0      ; video mode
oldrows   db 24     ; rows - 1
bAlt  db 0

	.code

;--- DS=DGROUP

InitVid proc
	push ds
	mov ax, 40h
	mov ds, ax
	mov dx, ds:[63h]
	pop ds
	xor dl, 60h
	mov [oldcrtp], dx
	mov al, 7
	cmp dl, 0B4h
	jz @F
	mov al, 3
@@:
	mov [oldmode], al

;--- to initially get the cursor pos of the alt screen, read the CRT.
;--- this code assumes that page 0 is active ( offset == 0 );
;--- could be fixed by reading CRT 0Ch/0Dh.

	mov al, 0eh
	out dx, al
	inc dx
	in al, dx
	mov ah, al
	dec dx
	mov al, 0fh
	out dx, al
	inc dx
	in al, dx
	mov bl, 80
	div bl
	xchg al, ah
	mov [oldcsrpos], ax
	ret
InitVid endp

;--- must be bimodal!
;--- ds=dgroup
;--- called by:
;---  dprintfr
;---  dprintfp
;---  vioproc

SwitchVid proc
	pusha
	mov dx, [oldcrtp]
	mov bx, [oldcols]
	mov ax, [oldmr]
	push ds
	push 40h
	pop ds
	mov cx, cs:[oldcsrpos]
	and byte ptr ds:[10h], not 30h
	cmp dl, 0b4h
	jnz @F
	or  byte ptr ds:[10h], 30h
@@:
	xchg bx,ds:[4Ah]
	xchg cx,ds:[50h]
	xchg dx,ds:[63h]
	xchg al,ds:[49h]
	xchg ah,ds:[84h]
	pop ds
	mov [oldcrtp], dx
	mov [oldcsrpos], cx
	mov [oldcols], bx
	mov [oldmr], ax
	popa
	ret
SwitchVid endp



;--- vio output for both real-mode and protected-mode

@getcursorpos macro
	movzx ebx, byte ptr ds:[462h];page
	mov bx, ds:[EBX*2+450h]
endm

@setcursorpos macro
	movzx ebx, byte ptr ds:[462h];page
	mov ds:[EBX*2+450h], ax
endm

writechar:
	smsw dx
	test dl,1
	jz @F
	mov ds:[ebx+esi], al
	retn
@@:
	push ds
	push 0b800h
	pop ds
	mov [bx], al
	pop ds
	retn

;--- print a char
;--- no registers modified

VioPutChar proc

local	wCols:word
local	bChar:byte
local	bRows:byte

	push ds
	pushad

	mov bChar, al
	mov dx, flatsel
	smsw ax
	test al,1
	jnz @F
	xor dx, dx
@@:
	push dx
	pop ds
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
	movzx ebx, bx
	call writechar
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
	smsw ax
	test al,1
	jnz @F
	push ds
	push 0B800h
	pop ds
	sub esi, 0B8000h
	call @F
	add esi, 0B8000h
	pop ds
	retn
@@:
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


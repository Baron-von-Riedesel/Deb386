
;--- dprintfp() - debug output for protected-mode
;--- preserves all registers, including flags.
;--- this code is 16-bit, but works on a 32-bit stack.

ifdef _DEBUG
@dprintfp macro text:req,a1,a2,a3,a4
local sym
	.data
sym db text,10,0
	.code
	for arg,<a4,a3,a2,a1>
	 ifnb <arg>
	  push arg
	 endif
	endm
	push offset sym
	call dprintfp
endm
endif

;--- ltob(long n, char * s, int base);
;--- value in dx:ax, outbuffer in cx, base in bx

ltob32 PROC uses edi

	movzx edi, bx	; base in edi
	push dx
	push ax
	pop eax		; number in eax
	mov bx,cx	; buffer in bx

	mov ch,0
	cmp di,-10
	jne @F
	mov di,10
	and eax,eax
	jns @F
	neg eax
	mov ch,'-'
@@:
	add bx,10
	mov BYTE PTR [bx],0
	dec bx
@@nextdigit:
	xor edx, edx
	div edi
	add dl,'0'
	cmp dl,'9'
	jbe @F
	add dl,7+20h
@@:
	mov [bx],dl
	dec bx
	and eax, eax
	jne @@nextdigit
	cmp ch,0
	je @F
	mov [bx],ch
	dec bx
@@:
	inc bx
	mov ax,bx
	ret

ltob32 ENDP

	.data

buff32 db 12 dup (?)	; using a static buffer to simplify things

	.code

;--- ds=unknown, ss don't need to be dgroup

dprintfp PROC

;local size_:word
;local flag:byte
;local longarg:byte
;local fill:byte

args    equ <[46]>
fmt     equ <word ptr [44]>
;oret    equ <[42]>
;esp     equ <[38]>
;regs    equ <[6]
;efl     equ <[2]
;ds      equ <[0]
size_   equ <word ptr [-2]>
flag    equ <byte ptr [-3]>
longarg equ <byte ptr [-4]>
fill    equ <byte ptr [-5]>

	push esp
	pushad
	pushfd
	push ds
	mov ebp, esp
	sub esp, 8
	mov ds, cs:[wKDDS]
	lea edi, args[ebp]
@@L335:
	mov si, fmt[ebp]
nextchar:
	lodsb
	or al,al
	je done
	cmp al,'%'
	je formatitem
	call handle_char
	jmp nextchar
done:
	mov esp, ebp
	sub edi, 2
	mov [ebp+38], edi	; set esp
	mov ax, [ebp+42]	; get return addr   
	mov ss:[edi], ax	; and store it at [esp]
	pop ds
	popfd
	popad
	pop esp
	ret

formatitem:
	push @@L335
	xor dx,dx
	mov longarg[ebp], dl
	mov bl,1
	mov cl,' '
	cmp BYTE PTR [si],'-'
	jne @F
	dec bx
	inc si
@@:
	mov flag[ebp], bl
	cmp BYTE PTR [si],'0'
	jne @F
	mov cl,'0'
	inc si
@@:
	mov fill[ebp], cl
	mov bx,dx

	.while byte ptr [si] >= '0' && byte ptr [si] <= '9'
		lodsb
		sub al,'0'
		cbw
		imul cx,bx,10		;cx = bx * 10
		add ax,cx
		mov bx,ax
	.endw

	mov size_[ebp],bx
	cmp BYTE PTR [si],'l'
	jne @F
	mov longarg[ebp], 1
	inc si
@@:
	lodsb
	mov fmt[ebp], si
	cmp al,'x'
	je handle_x
	cmp al,'X'
	je handle_x
	cmp al,'c'
	je handle_c
	cmp al,'d'
	je handle_d
	cmp al,'i'
	je handle_i
	cmp al,'s'
	je handle_s
	cmp al,'u'
	je handle_u
	cmp al,0
	jnz @@L359
	pop ax
	jmp done
handle_c:
	mov ax,ss:[edi]
	add edi,2
@@L359:
	call handle_char
	retn

handle_x:
	mov bx,16
	jmp @@lprt262
handle_d:
handle_i:
	mov bx,-10
	jmp @@lprt262
handle_u:
	mov bx,10
@@lprt262:
	mov ax,ss:[edi]
	add edi,2
	sub dx,dx
	cmp bx,0		;signed or unsigned?
	jge @F
	cwd
@@:
	cmp longarg[ebp],0
	je @F
	mov dx,ss:[edi]
	add edi,2
@@:
	mov cx, offset buff32
	call ltob32
	mov si, ax
	call output_string
	retn

handle_s:
	mov si,ss:[edi]
	add edi,2

output_string:	;display string at ds:si
	mov ax,si
	mov bx,size_[ebp]
	.while byte ptr [si]
		inc si
	.endw
	sub si,ax
	xchg ax,si
	sub bx,ax
	.if flag[ebp] == 1
		.while sword ptr bx > 0
			mov al, fill[ebp]
			call handle_char
			dec bx
		.endw
	.endif

	.while byte ptr [si]
		lodsb
		call handle_char
	.endw

	.while sword ptr bx > 0
		mov al, fill[ebp]
		call handle_char
		dec bx
	.endw
	retn

handle_char:

	cmp al,10
	jnz @F
	mov al,13
	call @F
	mov al,10
@@:
	mov ah,0Eh
	push 0
	push cs
	push 0
	call near ptr vioproc
	retn

args    equ <>
fmt     equ <>
size_   equ <>
flag    equ <>
longarg equ <>
fill    equ <>

dprintfp ENDP


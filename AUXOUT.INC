
;--- input/output COMx
;--- very simple implementation.

_PORT_		= 3F8h	;COM1
;_PORT_		= 2F8h	;COM2
_XONXOFF_	= 1
XON 		= 11h
XOFF		= 13h
EOT 		= 03H


;--- display a char in AL

AuxPutChar proc

	pusha

	mov dx, _PORT_
	add dx, 5			;LSR - Line Status Register
	mov cx, -1
	xchg al, ah
@@:
	in al, dx
	test al, 40h		;TEMT - transmitter empty?
	loopz @B
if _XONXOFF_
	test al, 1			;char received
	jz noxoff
	mov dx, _PORT_
	in al, dx
	cmp al, XOFF
	jnz noxoff
waitxon:
	add dx, 5
@@: 					;wait till new char arrived
	in al, dx
	test al, 1
	jz @B
	mov dx, _PORT_
	in al, dx
	cmp al, XON			;wait till XON received
	jnz waitxon
noxoff:
endif
	xchg al, ah
	mov dx, _PORT_
	out dx, al
	popa
	ret
AuxPutChar endp

;--- get a char in AL

AuxGetChar proc

	push cx
	push dx

	mov dx, _PORT_+6 	;MSR - modem status register
	in al, dx			;DSR - modem(=DCE) ready?
	and al, 20h
	jz error
	dec dx				;LSR - Line Status Register
@@:
	in al, dx
	test al, 01h		;DR - Data ready?
	jz @B
	mov dx, _PORT_
	in al, dx
	mov ah, 00
	jmp exit
error:
	xor ax, ax
exit:
	pop dx
	pop cx
	ret
AuxGetChar endp


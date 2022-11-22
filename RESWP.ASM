
;--- reset WP bit in CR0

	.286
	.model tiny
	.stack 256
	.dosseg
	.386p

	.code

start:
	mov eax, cr0
	btr eax, 16
	mov cr0, eax
	mov ah,4Ch
	int 21h

	END start

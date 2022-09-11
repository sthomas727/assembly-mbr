[ BITS 16 ]
mov ax, 0x2000
mov ds, ax

mov ax, 0xFFFF
jmp $


times 512-($-$$) db 0xFF
times 512 db 0xFF

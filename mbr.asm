; FAT12 bootloader
; Loads binary image in file "KRNL.BIN" into memory at 0x2000:0000, and executes it
; Boot drive number is provided in DL


[BITS 16]

jmp start
nop


; FAT 12 Header
;--------------------------------------
OEMLabel			  db "KRNLBOOT"
BytesPerSector        dw 512
SectorsPerCluster     db 1
NumberReservedSectors dw 1
NumberOfFats          db 2
MaxRootEntries        dw 224

TotalSectorCount      dw 2880
MediumByte			  db 0xF0
SectorsPerFat		  dw 9
SectorsPerTrack		  dw 18
NumberOfHeads         dw 2
HiddenSectors		  dd 0
LargeSectors		  dd 0
DriveNo				  dw 0
Signature			  db 41
VolumeID			  dd 0x00000000
VolumeLabel			  db "KRNLBOOT   "
FileSystem			  db "FAT12   "




start:
; Set up stack
	mov ax, 0x7c0
	mov ds, ax

	add ax, 544
	cli
	mov ss, ax
	mov sp, 4096
	sti
	mov [boot_device], dl

	mov ax, 19				; Read the root entry
	call lba_to_chs
	mov ax, ds
	mov es, ax

	mov bx, diskbuffer
	call chs_to_reg
	
	mov ah, 02h
	mov al, 14

	int 13h
	jc halt_loop			; Halt on error
	mov cx, 1				; Set counter to one to count directory entries

	xor ax, ax

.read_root:
	mov si, filename
	mov di, diskbuffer		; We will make this always point to the beginning of each entry
	add di, ax

	cmpsb
	je .match				; We have found the kernel entry
	inc cx
	

	cmp cx, 224				; There are 224 possible root entries
	jge .notfound  

	
	add ax, 32				; Move to next directory entry


	jmp .read_root

.notfound:
	mov si, file_missing  
	call puts
	jmp halt_loop


.match:
	mov ax, diskbuffer 
	mov ax, di 				; Restore value of DI after cmpsb

	add ax, 25				; Get logical sector in lower two bits
	
	mov si, ax
	mov ax, [si]
	mov [var_cluster], ax


	mov ax, 0x1				; Sector 1 = First sector of FAT
	call lba_to_chs 
	mov ax, ds
	mov es, ax

	mov bx, diskbuffer
	call chs_to_reg
	
	mov ah, 0x2
	mov al, 9 				; Read entire FAT into buffer


	int 13h					; int 13h disk services
	jc halt_loop			; Halt on error
load_kernel:
	mov ax, [var_cluster]

	add ax, 31				; Point to the start of the data area

	call lba_to_chs
	call chs_to_reg

	mov ax, 0x2000			; Load the first sector of our kernel to 0x2000:0000
	mov es, ax
	mov bx, [var_sector]	; var_sector is initialized to 0x0 for first iteration

	mov ah, 0x2
	mov al, 1
	int 13h
	jc halt_loop			; Halt on error

decode_fat:
	mov ax, [var_cluster]
	mov cx, 2
	xor dx, dx
	div word cx

	cmp dx, 0 				; DX = var_cluster % 2
	je .even
	


.odd:
; To get odd index: 8 bits in 1+(3*n)/2, high 4 bits in (3*n)/2    
	mov ax, [var_cluster]

	mov cx, 0x3
	xor dx, dx

	mul word cx
	mov cx, 0x2

	xor dx, dx
	div word cx

	xor si, si
	mov si, ax				; Store actual memory location of FAT index
	add si, 1				; FAT entries are zero-based, and we want 1+(3*n)/2
	add si, diskbuffer

	mov ax, [si]
	shl ax, 4				; 8 bits go in 0000 1234 5678 0000
	and ah, 0xF
	dec si
	mov bx, [si]
	and bl, 0xF0			; We only want the high 4 bits
	shr bl, 4				; and we want them in the low 4 positions.

	or al, bl
	jmp fat_read







.even:
; To get even index: Low four bits in 1+(3*n)/2, 8 bits in (3*n)/2
	
	mov ax, [var_cluster]

	mov cx, 0x3
	xor dx, dx

	mul word cx
	mov cx, 0x2

	xor dx, dx
	div word cx

	mov si, ax				; Store actual memory location of FAT index
	add si, 1				; FAT entries are zero-based, and we want 1+(3*n)/2
	add si, diskbuffer

	mov ax, [si]
	and ax, 0xF 			; We only want the low 4 bits
	mov ah, al				; 4 bits go in 0000 1234 0000 0000
	xor al, al

	dec si
	mov bx, [si]
	mov al, bl

fat_read:
	cmp ax, 0xFFF
	je .all_done

	mov [var_cluster], ax
	add word [var_sector], 512
	jmp load_kernel


.all_done:
	mov si, success
	call puts
	mov dl, [boot_device]
	jmp long 0x2000:0	






halt_loop:
	hlt
	jmp halt_loop

; puts: Print string to screen (zero-terminated)
;  si: Starting address of input string
puts:
	pusha
	mov ah, 0xE
	xor bh, bh
.loop:
	lodsb
	cmp al, 0x0
	je .done
	int 10h
	jmp .loop
.done:
	popa
	ret





; AX = quotient, DX = remainder
; Converts given LBA to CHS tuple
; ax = LBA Address
lba_to_chs:
	;pusha
	xor bx, bx
	mov bx, ax
	xor dx, dx


;    S = (LBA mod SPT) + 1
	div word [SectorsPerTrack]
	inc dl 						; Remainder is stored in DX
	mov [var_s], dl

;    H = (LBA / SPT) mod HPC
	xor dx, dx
	div word [NumberOfHeads]	; (LBA / SPT) already stored in AX from last operation
	mov [var_h], dl


;    C = LBA ÷ (HPC × SPT)
	xor dx, dx
	mov ax, [NumberOfHeads]
	mul word [SectorsPerTrack]
	mov cx, ax					; Store the result of (HPC*SPT) in CX
	mov ax, bx
	div cx						; LBA/CX
	mov [var_c], al


	;popa
	ret



; Move the values in the CHS variables to their correct registers
; Ensure correct values from lba_to_chs beforehand
chs_to_reg:
	xor cx, cx
	mov cl, [var_s]
	mov ch, [var_c]
	mov dh, [var_h]
	mov dl, [boot_device]

	ret



; Variables and constants
; ---------------------------------

disk_error 			db "Disk Error.",0xA,0x0
filename 			db "KRNL    BIN",0x0
success  			db "Kernel Loaded.",0x0
;filename 			db "FILE    BIN",0x0
file_missing		db "Cannot find KRNL.BIN",0x0

var_c 				db 0
var_h 				db 0
var_s 				db 0

var_cluster			dw 0 ; Position in FAT of kernel file
var_sector			dw 0

boot_device 		db 0

var_sect 			db 0


times 510-($-$$) 	db 0
bootSignature 	 	db 0x55,0xAA

diskbuffer:

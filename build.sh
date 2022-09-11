#!/bin/bash

if [ -a image.img ]
	then
	rm image.img
fi

mkdosfs -C image.img 1440 || exit
nasm -fbin mbr.asm
#dd seek=1 bs=512 count=2879 if=/dev/zero of=mbr
dd conv=notrunc if=mbr of=image.img
sudo mount -o loop image.img mntdir
#echo "Hello World!" | sudo tee mntdir/FILE.TXT > /dev/null
nasm -fbin krnl.asm -o krnl.bin
sudo cp krnl.bin mntdir/KRNL.BIN
sudo umount mntdir



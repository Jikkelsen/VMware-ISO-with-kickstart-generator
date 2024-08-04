#!/bin/bash

# Input variables
INPUT_TICK=$1
OUTPUT_NAME=$2

#Generate full path to input file
INPUTPATH="$(pwd)/.TempFiles/$INPUT_TICK/InputIsoContents"

#Take ownership of folder to generate iso
chmod 777 $INPUTPATH/*

#And build the final iso
genisoimage \
    -relaxed-filenames \
    -J \
    -R \
    -output Output/KickstartISOs/$OUTPUT_NAME \
    -b ISOLINUX.BIN \
    -c BOOT.CAT \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -e EFIBOOT.IMG \
    -no-emul-boot \
    -path-spec $INPUTPATH
#end
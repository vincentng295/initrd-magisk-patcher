#!/bin/sh
# Patcher

getdir() {
  case "$1" in
    */*)
      dir=${1%/*}
      if [ -z "$dir" ]; then
        echo "/"
      else
        echo "$dir"
      fi
    ;;
    *) echo "." ;;
  esac
}

SCPATH="$(getdir "$0")"
SCPATH="$(realpath "$SCPATH")"
INPUT="$SCPATH/input"
INITRD="$INPUT/initrd.img"
MAGISK="$INPUT/magisk.apk"
OUTPUT="$SCPATH/output"

# ==========================================
# STEP 1: Create work and magisk directories
# ==========================================

WORK_DIR="$SCPATH/work"
INITRD_OUT="$WORK_DIR/initrd"
MAGISK_OUT="$SCPATH/magisk"

echo "[*] Creating working directories..."
rm -rf "$WORK_DIR" "$MAGISK_OUT" "$OUTPUT" # Clean up previous builds if any
mkdir -p "$INITRD_OUT"
mkdir -p "$MAGISK_OUT"
mkdir -p "$OUTPUT"


# ==========================================
# STEP 2: Extract initrd.img to work/initrd
# ==========================================

if [ ! -f "$INITRD" ]; then
    echo "[-] Error: $INITRD not found!"
    exit 1
fi

echo "[*] Extracting $INITRD to $INITRD_OUT..."
{
    cd "$INITRD_OUT" || exit 1
    # Check if initrd is gzipped or raw cpio, using busybox compatible flags (-idmu)
    if gzip -t "$INITRD" 2>/dev/null; then
        gzip -dc "$INPUT/initrd.img" | cpio -idmu 2>/dev/null
    else
        cpio -idmu < "$INITRD" 2>/dev/null
    fi

    if [ $? -ne 0 ]; then
        echo "[-] Error: Failed to extract initrd.img"
        exit 1
    fi
}


# ==========================================
# STEP 3: Extract lib/x86_64 from magisk.apk
# ==========================================

if [ ! -f "$MAGISK" ]; then
    echo "[-] Error: $MAGISK not found!"
    exit 1
fi

echo "[*] Extracting lib/x86_64 from $MAGISK to $MAGISK_OUT..."

# Extract only the required architecture binaries to a temp location
TEMP_MAGISK="$WORK_DIR/magisk_tmp"
mkdir -p "$TEMP_MAGISK"
unzip -q "$MAGISK" "lib/x86_64/*" -d "$TEMP_MAGISK"
unzip -q "$MAGISK" "lib/x86/libmagisk.so" -d "$TEMP_MAGISK"

if [ $? -ne 0 ] || [ ! -d "$TEMP_MAGISK/lib/x86_64" ]; then
    echo "[-] Error: Failed to extract lib/x86_64 from Magisk APK"
    exit 1
fi

# Move the extracted binaries directly into the $SCPATH/magisk directory
mv "$TEMP_MAGISK"/lib/x86_64/* "$MAGISK_OUT/"
mv "$TEMP_MAGISK"/lib/x86/libmagisk.so "$MAGISK_OUT/libmagisk32.so"
rm -rf "$TEMP_MAGISK"


# ==========================================
# STEP 4: Create magiskbin and rename binaries
# ==========================================

MAGISKBIN_OUT="$INITRD_OUT/magiskbin"
echo "[*] Creating $MAGISKBIN_OUT and setting up renamed binaries..."
mkdir -p "$MAGISKBIN_OUT"

# Verify source files exist before copying and renaming
if [ -f "$MAGISK_OUT/libmagisk.so" ]; then
    cp "$MAGISK_OUT/libmagisk.so" "$MAGISKBIN_OUT/magisk64"
fi
if [ -f "$MAGISK_OUT/libmagisk32.so" ]; then
    cp "$MAGISK_OUT/libmagisk32.so" "$MAGISKBIN_OUT/magisk32"
fi

cp "$MAGISK_OUT/libmagiskpolicy.so" "$MAGISKBIN_OUT/magiskpolicy"

# Ensure binaries have execution rights inside the initrd environment
chmod 755 "$MAGISKBIN_OUT/magisk"*


# ==========================================
# STEP 5: Copy custom scripts and repack initrd
# ==========================================

SCRIPTS_SRC="$SCPATH/scripts"
SCRIPTS_DST="$INITRD_OUT/scripts"

if [ -d "$SCRIPTS_SRC" ]; then
    echo "[*] Copying custom scripts to $SCRIPTS_DST..."
    mkdir -p "$SCRIPTS_DST"
    dos2unix "$SCRIPTS_SRC"/*
    cp -r "$SCRIPTS_SRC"/* "$SCRIPTS_DST/"
    chmod +x "$SCRIPTS_DST"/* 2>/dev/null
else
    echo "[!] Warning: No source scripts directory found at $SCRIPTS_SRC. Skipping copy."
fi

echo "[*] Repacking initrd.img into $OUTPUT..."
cd "$INITRD_OUT" || exit 1

# Pack using cpio and compress back with maximum gzip compression
find . | cpio -H newc -o 2>/dev/null | gzip -9 > "$OUTPUT/initrd.img"

if [ $? -eq 0 ]; then
    echo "[+] Done! Your patched initrd.img is available at $OUTPUT/initrd.img"
else
    echo "[-] Error: Failed to repack initrd.img"
    exit 1
fi
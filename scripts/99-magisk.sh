#!/bin/sh
# 99-magisk by HuskyDG


TMP_PATH="debug_ramdisk"
SYS_PATH="/android/$TMP_PATH"
MAGISKBINDIR=/magiskbin

if false; then
mount() { echo "[MOCK MOUNT] mount $@"; }
mkdir() { echo "[MOCK MKDIR] mkdir $@"; }
cp() { echo "[MOCK CP] cp $@"; }
chmod() { echo "[MOCK CHMOD] chmod $@"; }
ln() { echo "[MOCK LN] ln $@"; }
fi

# Just use u:r:su:s0, magisk will auto set it to u:r:magisk:s0
# https://github.com/topjohnwu/Magisk/blob/14ea5cfb4a5771c742f7c3fd1e685bdbfac7aa8c/native/src/init/rootdir.rs#L13
MAGISKRC="
on post-fs-data
    exec u:r:su:s0 0 0 -- /$TMP_PATH/magiskpolicy --live
    exec u:r:su:s0 0 0 -- /$TMP_PATH/magisk --post-fs-data

on property:vold.decrypt=trigger_restart_framework
    exec u:r:su:s0 0 0 -- /$TMP_PATH/magisk --service

on nonencrypted
    exec u:r:su:s0 0 0 -- /$TMP_PATH/magisk --service

on property:sys.boot_completed=1
    exec u:r:su:s0 0 0 -- /$TMP_PATH/magisk --boot-complete
"

### FUNCTIONS

# Pure bash dirname implementation
getdir() {
  case "$1" in
    */*)
      dir=${1%/*}
      if [ -z $dir ]; then
        echo "/"
      else
        echo $dir
      fi
    ;;
    *) echo "." ;;
  esac
}

inject_line() {
    local file="$1"
    local content="$2"
    if [ -f "$file" ]; then
        echo "" >> "$file"
        echo "$content" >> "$file"
        echo "" >> "$file"
    else
        echo "[WARNING] Cannot inject content: $file does not exist."
    fi
}

patch_rc() {
    local path="$1"
    local dir="$(getdir "$path")"
    if [ "$dir" = "." ]; then
        mkdir -p "$SYS_PATH/.magisk/rootdir"
    else
        mkdir -p "$SYS_PATH/.magisk/rootdir/$dir"
    fi
    cp -af "/android/$path" "$SYS_PATH/.magisk/rootdir/$path"
    inject_line ""          "$SYS_PATH/.magisk/rootdir/$path"
    inject_line "$MAGISKRC" "$SYS_PATH/.magisk/rootdir/$path"
    inject_line ""          "$SYS_PATH/.magisk/rootdir/$path"
    chmod 644 "$SYS_PATH/.magisk/rootdir/$path"
    mount --bind "$SYS_PATH/.magisk/rootdir/$path" "/android/$path"
}

### SCRIPT START HERE

echo "- Setup Magisk tmpfs"

mount -t tmpfs -o mode=755 magisk "$SYS_PATH"

mkdir -p "$SYS_PATH/.magisk/rootdir"
for bin in magisk32 magisk64 magiskpolicy; do
    cp -af "$MAGISKBINDIR/$bin" "$SYS_PATH/$bin"
    chmod 755 "$SYS_PATH/$bin"
done
ln -s ./magisk64 "$SYS_PATH/magisk"

INITRC_NAME="system/etc/init/hw/init.rc"
# legacy init.rc (Android 10 and older)
[ -f "/android/$INITRC_NAME" ] || INITRC_NAME="init.rc"
echo "- Inject magisk.rc into init.rc: /$INITRC_NAME"
patch_rc "$INITRC_NAME"

echo "- Done!"

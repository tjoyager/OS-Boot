#!/usr/bin/env bash
set -euo pipefail

mkdir -p osboot
cd osboot

echo "Downloading Linux kernel 6.1.1..."
wget -qnc https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.1.1.tar.xz

echo "Preparing space-free build environment..."
BUILD_DIR="$(mktemp -d /tmp/osbuild.XXXX)"
cp linux-6.1.1.tar.xz "$BUILD_DIR"/

CURRENT_DIR="$(pwd)"
ARCH_NAME="$(uname -m)"

cd "$BUILD_DIR"
echo "Extracting kernel..."
tar -xf linux-6.1.1.tar.xz
cd linux-6.1.1

echo "Configuring minimal kernel..."

if [[ "$ARCH_NAME" == "aarch64" ]]; then

    echo "ARM64"

    make ARCH=arm64 defconfig

    ./scripts/config \
        --enable CONFIG_PRINTK \
        --enable CONFIG_FUTEX \
        --enable CONFIG_DEVTMPFS \
        --enable CONFIG_DEVTMPFS_MOUNT \
        --enable CONFIG_BLK_DEV_INITRD \
        --enable CONFIG_SERIAL_AMBA_PL011 \
        --enable CONFIG_SERIAL_AMBA_PL011_CONSOLE

    make ARCH=arm64 olddefconfig

    make ARCH=arm64 -j"$(nproc)" KCFLAGS="-Wno-error=format"

    cp arch/arm64/boot/Image "$CURRENT_DIR"/Image


else

    echo "x86_64"

    make allnoconfig

    ./scripts/config \
        --enable CONFIG_64BIT \
        --enable CONFIG_PRINTK \
        --enable CONFIG_FUTEX \
        --enable CONFIG_MULTIUSER \
        --enable CONFIG_POSIX_TIMERS \
        --enable CONFIG_HIGH_RES_TIMERS \
        --enable CONFIG_DEVPTS_FS \
        --enable CONFIG_BLK_DEV_INITRD \
        --enable CONFIG_TTY \
        --enable CONFIG_VT \
        --enable CONFIG_VT_CONSOLE \
        --enable CONFIG_HW_CONSOLE \
        --enable CONFIG_VGA_CONSOLE \
        --enable CONFIG_SERIAL_8250 \
        --enable CONFIG_SERIAL_8250_CONSOLE \
        --enable CONFIG_DEVTMPFS \
        --enable CONFIG_DEVTMPFS_MOUNT \
        --enable CONFIG_BINFMT_ELF \
        --enable CONFIG_BINFMT_SCRIPT \
        --enable CONFIG_PROC_FS \
        --enable CONFIG_SYSFS \
        --enable CONFIG_UNIX >/dev/null 2>&1

    make olddefconfig

    echo "Compiling minimal kernel (this will be MUCH faster)..."
    make -j"$(nproc)" KCFLAGS="-Wno-error=format"

    cp arch/x86/boot/bzImage "$CURRENT_DIR"/bzImage

fi

cd "$CURRENT_DIR"

rm -rf "$BUILD_DIR"


echo "Recreating minimal myramdisk layout..."
rm -rf myramdisk
mkdir -p myramdisk/{bin,dev,etc,home,proc,root,sys,tmp}
chmod 1777 myramdisk/tmp


if [[ "$ARCH_NAME" == "aarch64" ]]; then

    cp /usr/bin/busybox myramdisk/bin/

    cd myramdisk/bin

    ./busybox --install .

    cd ../../
fi

echo "Writing init script..."

if [[ "$ARCH_NAME" == "aarch64" ]]; then

cat > myramdisk/init << 'EOF'
#!/bin/sh

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

echo "Starting ARM64 minimal challenge rootfs..."

exec /bin/sh
EOF

else

cat > myramdisk/init << 'EOF'
#!/bin/busybox sh

echo "Starting minimal challenge rootfs..."

while true; do
  /bin/getty -L tty1 115200 vt100
  sleep 1
done
EOF

fi

chmod 755 myramdisk/init

echo "Packing initramfs..."
cd myramdisk
find . -print0 | cpio --null -ov --format=newc 2>/dev/null | gzip -9 > ../myramdisk.gz
cd ..

echo "Building baseline ISO layout..."
rm -rf mylinuxiso
mkdir -p mylinuxiso/boot/grub

if [[ "$ARCH_NAME" == "aarch64" ]]; then
    cp Image mylinuxiso/boot/Image
else
    cp bzImage mylinuxiso/boot/bzImage
fi

cp myramdisk.gz mylinuxiso/boot/myramdisk.gz

echo "Writing GRUB configuration..."

if [[ "$ARCH_NAME" == "aarch64" ]]; then

cat > mylinuxiso/boot/grub/grub.cfg << 'EOF'
set timeout=5
set default=0

menuentry "Linux Baseline ARM64" {
  linux /boot/Image console=ttyAMA0 rdinit=/init
  initrd /boot/myramdisk.gz
}
EOF

else

cat > mylinuxiso/boot/grub/grub.cfg << 'EOF'
set timeout=5
set default=0

menuentry "Linux Baseline" {
  linux /boot/bzImage
  initrd /boot/myramdisk.gz
}
EOF

fi

echo "Generating ISO image..."

grub-mkrescue -o mylinux.iso mylinuxiso

echo ""
echo "Project baseline recreated in: $(pwd)"
echo ""
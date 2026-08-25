#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  # echo "Skipping: this file is not meant to be sourced." >&2
  return 0
fi

DEVICE_NAME="lvm-image-disk"
for link in /dev/disk/by-id/*"${DEVICE_NAME}"; do
  [[ -e "$link" ]] || continue
  DISK=$(readlink -f "$link")
  break
done

BOOT_PART="${DISK}-part1"
LVM_PART="${DISK}-part2"

VG_NAME="vg_group"
ROOT_LV="/dev/${VG_NAME}/root"
DATA_LV="/dev/${VG_NAME}/data"

NEWROOT="/mnt/newroot"

echo "Installing required packages..."
dnf install -y lvm2 rsync xfsprogs grub2-tools grub2-pc grub2-pc-modules

echo "Partitioning disk ${DISK}..."
parted "$DISK" --script mklabel msdos

# /boot, primary, bootable
parted "$DISK" --script mkpart primary ext4 1MiB 1025MiB
parted "$DISK" --script set 1 boot on

# LVM
parted "$DISK" --script mkpart primary 1025MiB 100%
parted "$DISK" --script set 2 lvm on

partprobe ${DISK}
udevadm settle
lsblk ${DISK}


echo "Formatting partitions and setting up LVM..."
mkfs.ext4 -F "$BOOT_PART"

pvcreate -ff -y "$LVM_PART"
vgcreate "$VG_NAME" "$LVM_PART"

lvcreate -L 60G -n root "$VG_NAME"
lvcreate -l 100%FREE -n data "$VG_NAME"

mkfs.xfs -f "$ROOT_LV"
mkfs.xfs -f "$DATA_LV"

echo "Mounting new partitions..."
mkdir -p "$NEWROOT"
mount "$ROOT_LV" "$NEWROOT"

mkdir -p "$NEWROOT/boot"
mount "$BOOT_PART" "$NEWROOT/boot"

mkdir -p "$NEWROOT/data"
mount "$DATA_LV" "$NEWROOT/data"

echo "Copying system files..."
rsync -aAXH --numeric-ids --info=progress2 \
  --exclude=/dev/* \
  --exclude=/proc/* \
  --exclude=/sys/* \
  --exclude=/run/* \
  --exclude=/tmp/* \
  --exclude=/mnt/* \
  --exclude=/media/* \
  --exclude=/lost+found \
  / "$NEWROOT/"

echo "Updating fstab and GRUB configuration..."
echo "Updating fstab..."
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_LV")
BOOT_UUID=$(blkid -s UUID -o value "$BOOT_PART")
DATA_UUID=$(blkid -s UUID -o value "$DATA_LV")

ROOT_FS=$(blkid -s TYPE -o value "$ROOT_LV")
BOOT_FS=$(blkid -s TYPE -o value "$BOOT_PART")
DATA_FS=$(blkid -s TYPE -o value "$DATA_LV")

cat > "$NEWROOT/etc/fstab" <<EOF
UUID=$ROOT_UUID  /      $ROOT_FS  defaults  0 0
UUID=$BOOT_UUID  /boot  $BOOT_FS  defaults  0 2
UUID=$DATA_UUID  /data  $DATA_FS  defaults  0 0
EOF

echo "Preparing chroot..."
mount --bind /dev  "$NEWROOT/dev"
mount --bind /proc "$NEWROOT/proc"
mount --bind /sys  "$NEWROOT/sys"
mount --bind /run  "$NEWROOT/run"

chroot "$NEWROOT" /bin/bash -s -- "$DISK" "$VG_NAME" <<'CHROOT'
set -euo pipefail

CHROOT_DISK="$1"
VG_NAME="$2"

dnf install -y lvm2 grub2-tools grub2-pc grub2-pc-modules

cat > /etc/dracut.conf.d/storage.conf <<'EOF'
add_drivers+=" virtio_scsi "
add_drivers+=" sd_mod "
add_dracutmodules+=" lvm "
EOF

dracut -f --regenerate-all

CHROOT_ROOT_UUID=$(blkid -s UUID -o value "/dev/${VG_NAME}/root")

grubby --update-kernel=ALL --remove-args="root rd.lvm.lv rd.lvm.vg"
grubby --update-kernel=ALL --args="root=UUID=${CHROOT_ROOT_UUID} rd.lvm.lv=${VG_NAME}/root"

GRUB_DISABLE_OS_PROBER=true grub2-mkconfig -o /boot/grub2/grub.cfg

grub2-install --recheck "$CHROOT_DISK"

echo "Final kernel args:"
grubby --info=ALL | grep -E 'kernel=|args='
CHROOT

umount -R "$NEWROOT"
sync

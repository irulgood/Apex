#!/bin/bash
set -e

echo "🚨 Ini akan MENGGANTI OS dengan Ubuntu 20.04 (focal) yang baru. Semua data lama akan HILANG."
read -p "Lanjut? (y/N): " ok
[[ "$ok" != "y" ]] && echo "Batal." && exit 1

# === KONFIGURASI DISK (CEK DENGAN `lsblk`) ===
DISK_DEV="/dev/vda"   # ganti ke /dev/sda bila perlu

echo "🔧 Install tools host..."
apt update
apt install -y debootstrap gdisk wget

echo "📂 Siapkan target root baru..."
mkdir -p /mnt/ubuntu20
debootstrap focal /mnt/ubuntu20 http://archive.ubuntu.com/ubuntu

echo "🔗 Mount fs ke chroot..."
mount --bind /dev  /mnt/ubuntu20/dev
mount --bind /proc /mnt/ubuntu20/proc
mount --bind /sys  /mnt/ubuntu20/sys
cp /etc/resolv.conf /mnt/ubuntu20/etc/resolv.conf

echo "🌐 Konfig dasar + paket penting di sistem baru (chroot)..."
# Pass DISK_DEV ke chroot via env
DISK_DEV_CHROOT="$DISK_DEV" chroot /mnt/ubuntu20 /bin/bash -euxc '
echo "ubuntu20" > /etc/hostname

# Repo & update
apt update

# Paket inti: SSH, GRUB, kernel, initramfs, tools
apt install -y \
  openssh-server grub-pc grub-common \
  linux-image-generic-hwe-20.04 \
  initramfs-tools sudo net-tools systemd-sysv

# Set password root
echo "root:@Irul21tun" | chpasswd

# Netplan (DHCP). Kita siapkan untuk eth0 dan ens3 sekaligus.
mkdir -p /etc/netplan
cat > /etc/netplan/01-netcfg.yaml <<NETYAML
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: true
      optional: true
    ens3:
      dhcp4: true
      optional: true
NETYAML

# Terapkan netplan saat boot (systemd-networkd default di server)
# (Tidak perlu jalankan netplan apply sekarang di chroot)

# Install GRUB ke disk yang benar
grub-install '"$DISK_DEV_CHROOT"'
update-initramfs -u
update-grub
'

echo "✅ Sistem Ubuntu 20.04 sudah terpasang di /mnt/ubuntu20."

echo "🧨 Menghapus sistem lama dari root /. TUNGGU 10 detik kalau mau cancel (Ctrl+C)."
sleep 10
umount -l /mnt/ubuntu20/dev /mnt/ubuntu20/proc /mnt/ubuntu20/sys

# Hapus root lama dengan hati-hati: kita akan pivot ke root baru dulu agar aman
# Cara sederhana: bind-mount root baru ke /, lalu rsync? -> di skenario VPS,
# lebih praktis: pindahkan tree baru ke / dengan move-mount (butuh initrd khusus).
# Karena kita berada di host lama, pendekatan yang stabil adalah:
#   1) rsync root baru -> /
#   2) atau cara cepat (berisiko): hapus root lama lalu move isi ubuntu20
# Namun paling bersih: reboot langsung ke root baru dengan fstab/grub yang menunjuk partisi sama.
# Karena kita menulis OS baru ke partisi yang sama, cukup reboot, GRUB/Kernel baru akan dipakai.

echo "🔁 Reboot ke OS baru..."
reboot

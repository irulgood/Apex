#!/bin/bash

set -e

echo "🚨 PERINGATAN BESAR: Ini akan MENGHAPUS sistem lama dan menggantinya dengan Ubuntu 20.04."
read -p "Apakah kamu yakin ingin LANJUT? (y/N): " confirm
if [[ "$confirm" != "y" ]]; then
  echo "❌ Proses dibatalkan."
  exit 1
fi

echo "🔍 Mendeteksi disk utama..."
ROOT_DISK=$(lsblk -n -o NAME,MOUNTPOINT | grep " /$" | awk '{print $1}' | sed 's/[0-9]*$//')
DISK_DEV="/dev/${ROOT_DISK}"
echo "📦 Disk utama terdeteksi: $DISK_DEV"

echo "🔧 Memasang dependensi..."
apt update
apt install -y debootstrap gdisk grub-pc net-tools ifupdown systemd-sysv sudo

echo "📁 Membuat sistem Ubuntu 20.04 di /mnt/ubuntu20..."
mkdir -p /mnt/ubuntu20
debootstrap focal /mnt/ubuntu20 http://archive.ubuntu.com/ubuntu

echo "🔗 Mount virtual filesystem..."
mount --bind /dev /mnt/ubuntu20/dev
mount --bind /proc /mnt/ubuntu20/proc
mount --bind /sys /mnt/ubuntu20/sys
cp /etc/resolv.conf /mnt/ubuntu20/etc/

echo "🌐 Menyiapkan konfigurasi jaringan statik..."
cat > /mnt/ubuntu20/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

echo "🔧 Masuk ke sistem Ubuntu 20.04 (chroot) dan instalasi sistem..."
chroot /mnt/ubuntu20 /bin/bash <<'EOL'
echo "ubuntu20" > /etc/hostname
apt update
apt install -y ssh sudo net-tools ifupdown grub-pc systemd-sysv

echo "🔑 Silakan atur password root baru:"
passwd root

echo "📦 Memasang GRUB ke disk utama..."
grub-install /dev/vda
update-grub
EOL

echo "✅ Sistem Ubuntu 20.04 berhasil dipasang."

echo "🧨 Menghapus sistem lama (pastikan semua sukses sebelumnya)..."
umount -l /mnt/ubuntu20/dev /mnt/ubuntu20/proc /mnt/ubuntu20/sys
rm -rf /* --preserve-root

echo "🔁 Rebooting ke sistem Ubuntu 20.04 baru..."
reboot
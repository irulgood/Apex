#!/bin/bash
set -e

echo "🚨 PERINGATAN: INI AKAN MENGGANTI OS VPS KAMU DENGAN UBUNTU 20.04 BARU!"
echo "Seluruh data lama akan hilang! Pastikan sudah backup."
read -p "Lanjutkan debootstrap install Ubuntu 20.04? (y/N): " confirm
[[ "$confirm" != "y" ]] && echo "❌ Dibatalkan" && exit 1

DISK_DEV="/dev/vda"  # Ganti sesuai output lsblk (biasanya /dev/vda untuk DO, kadang /dev/sda di provider lain)

echo "🔧 Memasang tools penting..."
apt update
apt install -y debootstrap gdisk grub-pc net-tools ifupdown systemd-sysv sudo

echo "📁 Membuat sistem Ubuntu 20.04 baru di /mnt/ubuntu20..."
mkdir -p /mnt/ubuntu20
debootstrap focal /mnt/ubuntu20 http://archive.ubuntu.com/ubuntu

echo "🔗 Mount filesystem agar chroot bekerja..."
mount --bind /dev /mnt/ubuntu20/dev
mount --bind /proc /mnt/ubuntu20/proc
mount --bind /sys /mnt/ubuntu20/sys
cp /etc/resolv.conf /mnt/ubuntu20/etc/

echo "🌐 Setting konfigurasi jaringan dan SSH di sistem baru..."
chroot /mnt/ubuntu20 /bin/bash <<'EOL'
echo "ubuntu20" > /etc/hostname
apt update
apt install -y ssh grub-pc sudo net-tools ifupdown systemd-sysv

# Atur password root (otomatis: root123, GANTI SETELAH LOGIN!)
echo "root:@Irul21tun" | chpasswd

# Siapkan interfaces DHCP agar jaringan langsung hidup
mkdir -p /etc/network
cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

grub-install /dev/vda  # Ganti ke /dev/sda jika disk utama kamu /dev/sda
update-grub
EOL

echo "✅ Sistem Ubuntu 20.04 sudah terinstall di /mnt/ubuntu20."

echo "🧨 Menghapus seluruh sistem lama dari root / (PERMANEN, TIDAK BISA DIUNDO!)"
echo "   Tunggu 10 detik jika kamu mau cancel (Ctrl+C untuk batal)..."
sleep 10
umount -l /mnt/ubuntu20/dev /mnt/ubuntu20/proc /mnt/ubuntu20/sys
rm -rf /* --preserve-root

echo "🔁 Rebooting ke Ubuntu 20.04 baru..."
reboot

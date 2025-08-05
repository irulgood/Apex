#!/bin/bash
set -e

echo "⚠️ PERINGATAN: Ini akan men-downgrade VPS dari Ubuntu 22.04 ke 20.04"
read -p "Lanjutkan downgrade? (y/N): " confirm
[[ "$confirm" != "y" ]] && echo "❌ Dibatalkan" && exit 1

# Ganti repo ke focal (Ubuntu 20.04)
echo "🔧 Mengganti /etc/apt/sources.list ke focal..."
sudo sed -i 's/jammy/focal/g; s/kinetic/focal/g; s/lunar/focal/g' /etc/apt/sources.list

echo "🔄 Menjalankan apt update..."
sudo apt update
echo "📦 Menginstall aptitude..."
sudo apt install -y aptitude

echo "📉 Menjalankan full-upgrade untuk downgrade (aptitude)..."
sudo aptitude full-upgrade || true

echo "🧩 Memperbaiki konflik overwrite file (E: Tried to extract package...)"
sudo apt -o Dpkg::Options::="--force-overwrite" -f install

echo "🧠 Menginstall kernel Ubuntu 20.04 (5.15.0-144)..."
sudo apt install -y linux-image-5.15.0-144-generic linux-headers-5.15.0-144-generic

echo "📂 Membuat /etc/network kalau belum ada..."
sudo mkdir -p /etc/network

echo "🌐 Menulis konfigurasi DHCP ke /etc/network/interfaces..."
sudo tee /etc/network/interfaces > /dev/null <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

echo "🔁 Update GRUB..."
sudo update-grub

echo "✅ Downgrade selesai. Ubuntu kamu sekarang sudah berbasis repositori 20.04 (focal)"
read -p "Mau reboot sekarang? (y/N): " reboot
[[ "$reboot" == "y" ]] && sudo reboot || echo "❗ Silakan reboot manual nanti untuk menerapkan semua perubahan."

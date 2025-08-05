#!/bin/bash
set -e

echo "⚠️ PERINGATAN: Ini akan mengganti Ubuntu 22.04 jadi 20.04 dan bisa merusak sistem jika gagal."
read -p "Lanjut downgrade ke Ubuntu 20.04? (y/N): " confirm
[[ "$confirm" != "y" ]] && echo "❌ Batal" && exit 1

echo "🔧 Mengubah repo sources.list ke focal (20.04)..."
sudo sed -i 's/jammy/focal/g; s/kinetic/focal/g; s/lunar/focal/g' /etc/apt/sources.list

echo "🔄 Update repo dan install aptitude..."
sudo apt update
sudo apt install -y aptitude

echo "📦 Melakukan full-upgrade dengan aptitude (interaktif)..."
sudo aptitude full-upgrade || true

echo "🛠️ Memperbaiki konflik file yang overwrite (E: Tried to extract...)"
sudo apt -o Dpkg::Options::="--force-overwrite" -f install

echo "🧩 Menginstal kernel Ubuntu 20.04 (opsional, stabil)..."
sudo apt install -y linux-image-5.15.0-144-generic linux-headers-5.15.0-144-generic

echo "📂 Pastikan folder konfigurasi jaringan ada..."
sudo mkdir -p /etc/network

echo "🌐 Setup konfigurasi jaringan DHCP..."
sudo tee /etc/network/interfaces >/dev/null <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

echo "🔁 Update GRUB bootloader..."
sudo update-grub

echo "✅ Downgrade selesai. Kamu bisa reboot sekarang."
read -p "Reboot sekarang? (y/N): " reboot_now
[[ "$reboot_now" == "y" ]] && sudo reboot || echo "🚨 Silakan reboot manual nanti untuk menyelesaikan downgrade."

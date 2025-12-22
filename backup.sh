#!/bin/bash
# ==========================================
# AUTO BACKUP + TELEGRAM NOTIFY
# BY KHOIRUL AMIR

# === CONFIG TELEGRAM ===
BOT_TOKEN="8300633089:AAG37Nd2bf_65SD_tItsJypQ2gDGejc5yKc"
CHAT_ID="5376506914"
TIME="10"
URL="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"

# === INFO VPS ===
IP=$(curl -sS ipv4.icanhazip.com)
domain=$(cat /etc/xray/domain 2>/dev/null)
date=$(date +"%Y-%m-%d")

# === PROSES BACKUP ===
echo "Proses backup sedang berlangsung..."
rm -rf /root/backup
mkdir -p /root/backup

cp /etc/passwd backup/
cp /etc/group backup/
cp /etc/shadow backup/
cp /etc/gshadow backup/
cp /etc/crontab backup/
cp -r /var/lib/kyt/ backup/kyt 2>/dev/null
cp -r /etc/xray backup/xray 2>/dev/null
cp -r /var/www/html/ backup/html 2>/dev/null

cd /root
zip -r $IP-$date.zip backup > /dev/null 2>&1

# === UPLOAD KE GOOGLE DRIVE ===
rclone copy /root/$IP-$date.zip dr:backup/ --progress
url=$(rclone link "dr:backup/$IP-$date.zip")
id=$(echo "$url" | grep -o '[-_a-zA-Z0-9]\{25,\}')
link="https://drive.google.com/u/4/uc?id=${id}&export=download"

# === SIAPKAN PESAN ===
TEXT="◇━━━━━━━━━━━━━━◇
⚠️ BACKUP OTOMATIS ⚠️
Detail Backup VPS
◇━━━━━━━━━━━━━━◇
IP VPS  : ${IP}
DOMAIN  : ${domain}
Tanggal : ${date}
◇━━━━━━━━━━━━━━◇
Link Backup : ${link}
◇━━━━━━━━━━━━━━◇
Backup dibuat otomatis setiap hari.
BY BOT : @Kamirr21
"

# === KIRIM PESAN BIASA KE TELEGRAM ===
curl -s --max-time $TIME \
     --data-urlencode "text=$TEXT" \
     -d "chat_id=$CHAT_ID&parse_mode=HTML&disable_web_page_preview=1" \
     $URL >/dev/null

# === HAPUS FILE SEMENTARA ===
rm -rf /root/backup
rm -f /root/$IP-$date.zip

echo "✅ Backup harian selesai dan notifikasi terkirim ke Telegram!"

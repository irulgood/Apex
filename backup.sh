#!/bin/bash
# ==========================================
# AUTO BACKUP + TELEGRAM NOTIFY (No Email)
# BY KHOIRUL AMIR

# === CONFIG TELEGRAM ===
BOT_TOKEN="8379519489:AAE6YLcEi9ilkkQmtXHZWM_WYhd4m2mDEJw"  # Ganti token kamu
CHAT_ID="5376506914"                                         # Ganti chat ID kamu

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
url=$(rclone link dr:backup/$IP-$date.zip)
id=$(echo "$url" | grep -oP 'id=\K[^&]+')
link="https://drive.google.com/u/4/uc?id=${id}&export=download"

# === KIRIM NOTIF TELEGRAM ===
TEXT=$(echo -e "<code>◇━━━━━━━━━━━━━━◇</code>\n<b>⚠️ BACKUP OTOMATIS ⚠️</b>\n<b>Detail Backup VPS</b>\n<code>◇━━━━━━━━━━━━━━◇</code>\n<b>IP VPS :</b> <code>${IP}</code>\n<b>DOMAIN :</b> <code>${domain}</code>\n<b>Tanggal :</b> <code>${date}</code>\n<code>◇━━━━━━━━━━━━━━◇</code>\n<b>Link Backup :</b> ${link}\n<code>◇━━━━━━━━━━━━━━◇</code>\n<code>Backup dibuat otomatis setiap hari.</code>\n<code>BY BOT : @Kamirr21</code>")

curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
-d chat_id="$CHAT_ID" \
-d "parse_mode=HTML" \
-d "disable_web_page_preview=true" \
-d text="$TEXT"

# === HAPUS FILE SEMENTARA ===
rm -rf /root/backup
rm -f /root/$IP-$date.zip

echo "✅ Backup harian selesai dan terkirim ke Telegram!"

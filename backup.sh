#!/bin/bash
# ==========================================
# AUTO BACKUP + TELEGRAM NOTIFY (No Email)
# BY KHOIRUL AMIR

# === CONFIG TELEGRAM ===
BOT_TOKEN="8379519489:AAE6YLcEi9ilkkQmtXHZWM_WYhd4m2mDEJw"   # Ganti dengan token bot kamu
CHAT_ID="5376506914"                                # Ganti dengan chat id kamu
export TIME="10"
export URL="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"

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
id=$(echo $url | grep '^https' | cut -d'=' -f2)
link="https://drive.google.com/u/4/uc?id=${id}&export=download"

# === KIRIM NOTIF TELEGRAM ===
TEXT="
<code>◇━━━━━━━━━━━━━━◇</code>
<b>   ⚠️ BACKUP OTOMATIS ⚠️</b>
<b>     Detail Backup VPS</b>
<code>◇━━━━━━━━━━━━━━◇</code>
<b>IP VPS  :</b> <code>${IP}</code>
<b>DOMAIN :</b> <code>${domain}</code>
<b>Tanggal :</b> <code>${date}</code>
<code>◇━━━━━━━━━━━━━━◇</code>
<b>Link Backup :</b> $link
<code>◇━━━━━━━━━━━━━━◇</code>
<code>Backup dibuat otomatis setiap hari.</code>
<code>BY BOT : @Kamirr21</code>
"

curl -s --max-time $TIME \
    -d "chat_id=$CHAT_ID&disable_web_page_preview=1&text=$TEXT&parse_mode=html" \
    $URL >/dev/null

# === HAPUS FILE SEMENTARA ===
rm -rf /root/backup
rm -f /root/$IP-$date.zip

echo "✅ Backup harian selesai dan terkirim ke Telegram!"
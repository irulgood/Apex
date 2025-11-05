#!/bin/bash
# =========================================
# Auto setup backup.sh dari GitHub + Cronjob
# By: IRUL TUN
# =========================================

# Ganti link di bawah ini dengan link RAW file backup.sh kamu di GitHub
GITHUB_URL="https://raw.githubusercontent.com/irulgood/Apex/ZX/backup.sh"

# Lokasi simpan script backup
TARGET="/root/backup.sh"

echo "⬇️  Downloading backup.sh dari GitHub..."
wget -q -O "$TARGET" "$GITHUB_URL"

if [ -f "$TARGET" ]; then
    echo "✅ File berhasil diunduh ke $TARGET"
else
    echo "❌ Gagal download file dari GitHub. Cek URL-nya ya."
    exit 1
fi

# Kasih izin eksekusi
chmod +x "$TARGET"

# Tambahkan cronjob jika belum ada
CRON_JOB="0 21 * * * /bin/bash $TARGET"

# Cek apakah cron sudah ada
if crontab -l 2>/dev/null | grep -q "$TARGET"; then
    echo "ℹ️  Cronjob sudah ada, gak perlu ditambah lagi."
else
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "🕒 Cronjob berhasil ditambahkan (backup tiap jam 21:00)."
fi

echo "🚀 Setup selesai! Backup otomatis aktif tiap malam."

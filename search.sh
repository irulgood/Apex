#!/bin/bash
# ==============================================
# AUTO UPDATE PANEL FILES (HTML + PHP)
# BY IRUL TUN
# ==============================================

# Folder tujuan
DEST="/var/www/html"

# URL file GitHub RAW
# Ganti dengan link raw GitHub kamu
GITHUB_RAW="https://raw.githubusercontent.com/USERNAME/REPO/main"

# Daftar file yang mau diambil
FILES=("search.html" "list_templates.php")

echo "🔄 Mulai update file dari GitHub..."
cd "$DEST" || { echo "❌ Gagal masuk ke $DEST"; exit 1; }

for FILE in "${FILES[@]}"; do
    echo "📥 Mengunduh $FILE ..."
    wget -q -O "$FILE" "$GITHUB_RAW/$FILE"
    if [ $? -eq 0 ]; then
        echo "✅ $FILE berhasil diperbarui."
    else
        echo "⚠️ Gagal update $FILE."
    fi
done

# Perbaiki izin file
chmod 644 "$DEST"/*.html "$DEST"/*.php
chown www-data:www-data "$DEST"/*.html "$DEST"/*.php

# Reload nginx
echo "🔁 Reload nginx..."
systemctl reload nginx

echo "🎉 Selesai update semua file!"
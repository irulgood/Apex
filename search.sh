#!/bin/bash
# ==============================================
# AUTO SETUP + UPDATE PANEL IRUL TUN
# ==============================================

DEST="/var/www/html"
GITHUB_RAW="https://raw.githubusercontent.com/irulgood/Apex/ZX"   # Repositori kamu
FILES=("search.html" "list_templates.php")
PHP_VERSION="7.4"   # Ganti sesuai versi PHP yang kamu pakai (cek: ls /run/php/)

echo "=============================================="
echo "🚀  SETUP PANEL & PHP FOR NGINX PORT 81"
echo "=============================================="
sleep 1

# --- Pastikan PHP & NGINX ada ---
echo "🔧 Memastikan nginx dan PHP-FPM terinstal..."
apt update -y >/dev/null 2>&1
apt install -y nginx php php-fpm wget >/dev/null 2>&1

# --- Cek socket PHP ---
PHP_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"
if [ ! -S "$PHP_SOCK" ]; then
    echo "⚠️  Socket PHP-FPM tidak ditemukan, menyalakan service..."
    systemctl start php${PHP_VERSION}-fpm
    systemctl enable php${PHP_VERSION}-fpm
fi

# --- Download file dari GitHub ---
echo "📥 Mengunduh file panel dari GitHub..."
cd "$DEST" || exit
for FILE in "${FILES[@]}"; do
    echo "→ $FILE"
    wget -q -O "$FILE" "$GITHUB_RAW/$FILE"
done

chmod 644 "$DEST"/*.html "$DEST"/*.php
chown www-data:www-data "$DEST"/*.html "$DEST"/*.php

# --- Buat konfigurasi nginx untuk port 81 ---
echo "⚙️  Mengatur konfigurasi Nginx port 81..."
cat >/etc/nginx/sites-enabled/panel81.conf <<EOF
server {
    listen 81;
    server_name _;
    root /var/www/html;
    index search.html index.php index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCK};
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# --- Tes konfigurasi & reload nginx ---
echo "🔁 Mengecek konfigurasi nginx..."
nginx -t && systemctl reload nginx

# --- Uji PHP-FPM ---
if systemctl is-active --quiet php${PHP_VERSION}-fpm; then
    echo "✅ PHP-FPM aktif (php${PHP_VERSION}-fpm)"
else
    echo "❌ PHP-FPM gagal berjalan. Coba periksa manual."
fi

# --- Tes file contoh ---
echo "<?php echo 'PHP OK'; ?>" > /var/www/html/test.php

echo
echo "🎉 Selesai! Sekarang coba buka di browser:"
echo "👉 http://$(hostname -I | awk '{print $1}'):81/search.html"
echo
echo "Atau cek PHP:"
echo "👉 http://$(hostname -I | awk '{print $1}'):81/test.php"
echo
echo "=============================================="

#!/bin/bash

# File konfigurasi
XRAY_LOG="/var/log/xray/access.log"
SSH_LOG="/var/log/auth.log"
XRAY_CONF_DIR="/etc/xray"
IFACE="eth0"  # Ganti dengan interface aktif dari hasil `vnstat --iflist`

echo "📊 Ringkasan Penggunaan Akun Xray/SSH"
echo "--------------------------------------------------"

# 🧠 Cek interface tersedia
if ! vnstat -i "$IFACE" &>/dev/null; then
  echo "❌ Interface '$IFACE' tidak ditemukan di vnstat."
  exit 1
fi

# Ambil total pemakaian bandwidth (rx + tx) dalam byte
total_bytes=$(vnstat --oneline -i "$IFACE" | awk -F\; '{print $(NF-4) + $(NF-2)}')
total_bytes=$(echo "$total_bytes" | awk '{printf "%.0f", $1 * 1024 * 1024}')

# Ambil semua user Xray dari access.log
xray_users=$(grep -oP "email: ?\K\S+" "$XRAY_LOG" | sort -u)

# Ambil user SSH
if [[ -f "$SSH_LOG" ]]; then
  ssh_users=$(grep -oP "Accepted .* for \K\S+" "$SSH_LOG" | sort -u)
else
  ssh_users=""
fi

# Gabungkan semua user
user_list=$(echo -e "$xray_users\n$ssh_users" | sort -u)

# Hitung total IP dari semua user
total_ip_all=0
declare -A ip_per_user
declare -A type_per_user

for user in $user_list; do
  ip_list=""
  akun_type="❓Unknown"

  # IP & Jenis Akun untuk user Xray
  if grep -q "email: *$user" "$XRAY_LOG"; then
    ip_list=$(grep "email: *$user" "$XRAY_LOG" | awk '{print $3}' | sort -u)
    for file in "$XRAY_CONF_DIR"/*.json; do
      if grep -q "$user" "$file"; then
        if grep -q '"protocol": *"vmess"' "$file"; then
          akun_type="VMess"
          break
        elif grep -q '"protocol": *"vless"' "$file"; then
          akun_type="VLess"
          break
        elif grep -q '"password"' "$file"; then
          akun_type="Trojan"
          break
        fi
      fi
    done
  fi

  # Jika user SSH
  if grep -q "Accepted .* for $user" "$SSH_LOG"; then
    akun_type="SSH"
    ssh_ip=$(grep "Accepted .* for $user" "$SSH_LOG" | grep -oP "from \K[\d\.]+" | sort -u)
    ip_list=$(echo -e "$ip_list\n$ssh_ip" | sort -u)
  fi

  ip_count=$(echo "$ip_list" | grep -v '^$' | wc -l)

  type_per_user["$user"]=$akun_type
  ip_per_user["$user"]=$ip_count
  total_ip_all=$((total_ip_all + ip_count))
done

# 🔁 Estimasi bandwidth per user berdasarkan jumlah IP
for user in "${!ip_per_user[@]}"; do
  ip_count=${ip_per_user[$user]}
  akun_type=${type_per_user[$user]}
  
  if (( ip_count == 0 || total_ip_all == 0 )); then
    est_mb="0.00"
  else
    user_bytes=$((total_bytes * ip_count / total_ip_all))
    est_mb=$(awk "BEGIN {printf \"%.2f\", $user_bytes / 1024 / 1024}")
  fi

  echo "👤 User        : $user"
  echo "📦 Jenis Akun : $akun_type"
  echo "🔢 Jumlah IP  : $ip_count"
  echo "📶 Estimasi BW: $est_mb MB"
  echo "--------------------------------------------------"
done
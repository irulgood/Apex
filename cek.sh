#!/bin/bash

CONFIG="/etc/xray/config.json"
XRAY_LOG="/var/log/xray/access.log"
IFACE="eth0"  # Ganti sesuai interface aktif (cek dengan: vnstat --iflist)
TODAY=$(date +%Y-%m-%d)

echo "📅 Hari ini: $TODAY"
echo "📊 Laporan Akun Xray Aktif"
echo "------------------------------------------------------------"

# Cek interface vnstat
if ! vnstat -i "$IFACE" &>/dev/null; then
  echo "❌ Interface '$IFACE' tidak ditemukan oleh vnstat!"
  exit 1
fi

# Ambil total bandwidth dari vnstat (dalam byte)
total_bytes=$(vnstat --oneline -i "$IFACE" | awk -F\; '{print $(NF-4) + $(NF-2)}')
total_bytes=$(echo "$total_bytes" | awk '{printf "%.0f", $1 * 1024 * 1024}')

declare -A ip_per_user
declare -A proto_per_user
declare -A expire_per_user
declare -a user_list
total_ip_all=0
protocol=""
last_user=""
last_expire=""

while IFS= read -r line; do
  # Ambil protokol terakhir
  if echo "$line" | grep -q '"protocol":'; then
    protocol=$(echo "$line" | grep -oP '"protocol":\s*"\K[^"]+')
  fi

  # Tangkap komentar ### user tanggal
  if [[ "$line" =~ ^### ]]; then
    last_user=$(echo "$line" | awk '{print $2}')
    last_expire=$(echo "$line" | awk '{print $3}')
    expire_per_user["$last_user"]=$last_expire
  fi

  # Tangkap email, cocokkan dengan user dari komentar sebelumnya
  if echo "$line" | grep -q '"email":'; then
    email=$(echo "$line" | grep -oP '"email":\s*"\K[^"]+')
    if [[ "$email" == "$last_user" ]]; then
      user_list+=("$email")
      proto_per_user["$email"]=$protocol
    fi
  fi
done < "$CONFIG"

# Hitung IP unik untuk user aktif
for user in "${user_list[@]}"; do
  expire=${expire_per_user[$user]}
  if [[ "$expire" < "$TODAY" ]]; then
    continue
  fi

  ip_list=$(grep "email: *$user" "$XRAY_LOG" | grep -oP '\d{1,3}(\.\d{1,3}){3}' | sort -u)
  ip_count=$(echo "$ip_list" | grep -v '^$' | wc -l)
  ip_per_user["$user"]=$ip_count
  total_ip_all=$((total_ip_all + ip_count))
done

# Tampilkan laporan akhir
for user in "${user_list[@]}"; do
  expire=${expire_per_user[$user]}
  if [[ "$expire" < "$TODAY" ]]; then
    continue
  fi

  ip_count=${ip_per_user[$user]:-0}
  akun_type=${proto_per_user[$user]:-Unknown}

  if (( ip_count == 0 || total_ip_all == 0 )); then
    est_mb="0.00"
  else
    user_bytes=$((total_bytes * ip_count / total_ip_all))
    est_mb=$(awk "BEGIN {printf \"%.2f\", $user_bytes / 1024 / 1024}")
  fi

  echo "👤 User        : $user"
  echo "📦 Jenis Akun : $akun_type"
  echo "📅 Expired    : $expire"
  echo "🔢 Jumlah IP  : $ip_count"
  echo "📶 Estimasi BW: $est_mb MB"
  echo "------------------------------------------------------------"
done

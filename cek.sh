#!/bin/bash

# === Konfigurasi umum ===
XRAY_LOG="/var/log/xray/access.log"
WINDOW_MIN=15          # jendela waktu "aktif": 15 menit terakhir
SHOW_IP_LIST=true      # true: tampilkan daftar IP aktif; false: hanya jumlahnya
HIDE_EXPIRED=true      # true: sembunyikan user yang sudah lewat tanggal expire

# === Inisialisasi waktu ===
TODAY=$(date +%F)
CUTOFF=$(date -d "-${WINDOW_MIN} minutes" +%s)

# === Fungsi: ambil IP AKTIF untuk user tertentu dalam WINDOW_MIN menit terakhir ===
active_ips_for_user() {
  local user="$1"
  # Ambil IP yang tercatat untuk "email: user" dalam access.log,
  # hanya jika timestamp baris >= CUTOFF
  awk -v user="$user" -v cutoff="$CUTOFF" '
    # Contoh baris log:
    # 2025/08/01 12:45:01 203.0.113.10 accepted tcp:... email:risky
    $0 ~ ("email:[[:space:]]*" user) {
      date=$1; time=$2
      # Pastikan format tanggal & waktu valid
      if (date ~ /^[0-9]{4}\/[0-9]{2}\/[0-9]{2}$/ && time ~ /^[0-9]{2}:[0-9]{2}:[0-9]{2}$/) {
        cmd = "date -d \"" date " " time "\" +%s"
        cmd | getline ts
        close(cmd)
        if (ts >= cutoff) {
          if (match($0, /([0-9]{1,3}\.){3}[0-9]{1,3}/, m)) ips[m[0]]=1
        }
      }
    }
    END { for (i in ips) print i }
  ' "$XRAY_LOG"
}

echo "📊 Laporan Akun Xray (IP AKTIF dalam ${WINDOW_MIN} menit terakhir)"
echo "=================================================================="

# === Daftar protokol yang dicek ===
for proto in vmess vless trojan shadowsocks; do
  DB_PATH="/etc/${proto}/.${proto}.db"
  LIMIT_FILE_BASE="/etc/limit/${proto}/quota"

  if [[ ! -f "$DB_PATH" ]]; then
    echo "❌ Database tidak ditemukan: $DB_PATH"
    echo "------------------------------------------------------------------"
    continue
  fi

  echo "🔹 Jenis Akun: ${proto^^}"

  # Format: "### <user> <expire> <uuid> <used_bytes>"
  grep -a "^###" "$DB_PATH" | while read -r tag user expire uuid used; do
    # Filter expired jika diinginkan
    if [[ "$HIDE_EXPIRED" == "true" && "$expire" < "$TODAY" ]]; then
      continue
    fi

    # Normalisasi 'used'
    [[ "$used" =~ ^[0-9]+$ ]] || used=0
    used_gb=$(awk "BEGIN {printf \"%.2f\", $used / 1024 / 1024 / 1024}")

    # Ambil IP aktif
    active_ips="$(active_ips_for_user "$user")"
    ip_count=$(printf "%s\n" "$active_ips" | grep -v '^[[:space:]]*$' | wc -l)

    # (Opsional) Sisa kuota jika file ada
    quota_file="${LIMIT_FILE_BASE}/${user}"
    if [[ -f "$quota_file" ]]; then
      quota_byte=$(cat "$quota_file")
      quota_gb=$(awk "BEGIN {printf \"%.2f\", $quota_byte / 1024 / 1024 / 1024}")
      quota_status="✅"
    else
      quota_gb="0.00"
      quota_status="❌"
    fi

    # Output
    echo "👤 User        : $user"
    echo "📦 Jenis Akun : $proto"
    echo "📅 Expired    : $expire"
    echo "📊 Dipakai    : $used_gb GB"
    echo "💾 Kuota Sisa : $quota_gb GB ($quota_status)"
    echo "🔢 IP Aktif   : $ip_count"
    if [[ "$SHOW_IP_LIST" == "true" ]]; then
      if [[ "$ip_count" -gt 0 ]]; then
        # tampilkan IP aktif dalam satu baris, dipisah spasi
        one_line_ips=$(echo "$active_ips" | xargs echo)
        echo "🌐 Daftar IP   : $one_line_ips"
      else
        echo "🌐 Daftar IP   : -"
      fi
    fi
    echo "------------------------------------------------------------------"
  done
done

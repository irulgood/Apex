#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "🚨 AKAN MENGGANTI OS ke Ubuntu 20.04 (focal). Semua data lama HILANG."
read -p "Lanjut? (y/N): " ok
[[ "${ok}" != "y" ]] && echo "Batal." && exit 1

# ---------- Helper ----------
wait_apt_clear() {
  echo "⏳ Menunggu APT/dpkg selesai..."
  systemctl stop apt-daily.service apt-daily-upgrade.service unattended-upgrades 2>/dev/null || true
  systemctl stop apt-daily.timer  apt-daily-upgrade.timer  2>/dev/null || true
  local t=0
  while pgrep -x apt >/dev/null || pgrep -x apt-get >/dev/null || pgrep -x dpkg >/dev/null; do
    ((t++)); [[ $t -gt 60 ]] && { echo "⚠️ paksa stop apt/dpkg"; killall apt apt-get dpkg 2>/dev/null || true; break; }
    sleep 2
  done
  rm -f /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock || true
  dpkg --configure -a || true
}
ensure_dev_null() {
  rm -f /dev/null || true
  mknod -m 666 /dev/null c 1 3 || true
  chown root:root /dev/null || true
}

# ---------- Deteksi disk/partisi ----------
ROOT_PART="$(findmnt -no SOURCE /)"; [[ -z "$ROOT_PART" ]] && { echo "Gagal deteksi root partition"; exit 1; }
PKNAME="$(lsblk -no PKNAME "$ROOT_PART" || true)"; [[ -z "$PKNAME" ]] && PKNAME="$(basename "$ROOT_PART" | sed 's/[0-9]*$//')"
DISK_DEV="/dev/${PKNAME}"
FSTYPE="$(findmnt -no FSTYPE / || echo ext4)"
ROOT_UUID="$(blkid -s UUID -o value "$ROOT_PART" || true)"
echo "🧭 ROOT_PART=$ROOT_PART  DISK_DEV=$DISK_DEV  FSTYPE=$FSTYPE  UUID=$ROOT_UUID"

# ---------- Host: pastikan APT siap ----------
ensure_dev_null
wait_apt_clear

echo "🔧 Install tools (host)…"
apt-get update
apt-get install -y debootstrap gdisk wget gpgv gnupg2 ca-certificates rsync

echo "📁 Bootstrap focal ke /mnt/ubuntu20…"
mkdir -p /mnt/ubuntu20
if [[ ! -x /mnt/ubuntu20/bin/sh ]]; then
  debootstrap focal /mnt/ubuntu20 http://archive.ubuntu.com/ubuntu
else
  echo "ℹ️  /mnt/ubuntu20 sudah ada — lewati debootstrap."
fi

echo "🔗 Bind-mount chroot…"
mountpoint -q /mnt/ubuntu20/dev  || mount --bind /dev  /mnt/ubuntu20/dev
mountpoint -q /mnt/ubuntu20/proc || mount --bind /proc /mnt/ubuntu20/proc
mountpoint -q /mnt/ubuntu20/sys  || mount --bind /sys  /mnt/ubuntu20/sys
cp /etc/resolv.conf /mnt/ubuntu20/etc/resolv.conf
rm -f /mnt/ubuntu20/dev/null || true; mknod -m 666 /mnt/ubuntu20/dev/null c 1 3 || true; chown root:root /mnt/ubuntu20/dev/null || true

echo "🌐 Konfigurasi sistem baru (chroot)…"
export DISK_DEV ROOT_UUID FSTYPE
chroot /mnt/ubuntu20 /bin/bash -eux <<'CHROOT'
export DEBIAN_FRONTEND=noninteractive

# Pastikan index OK
apt-get update

# Paket dasar OS (pakai force-overwrite utk cegah konflik file)
apt-get -o Dpkg::Options::="--force-overwrite" install -y \
  linux-image-generic-hwe-20.04 initramfs-tools \
  grub-pc grub-common \
  openssh-server sudo net-tools systemd-sysv netplan.io \
  ca-certificates curl wget gnupg xz-utils tar unzip iproute2 lsb-release \
  rsyslog cron logrotate jq

# Hostname
echo "ubuntu20" > /etc/hostname

# SSH root + password
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || true
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
echo 'UsePAM yes' >> /etc/ssh/sshd_config
ssh-keygen -A
echo "root:@Irul21tun" | chpasswd
systemctl enable ssh || true

# Netplan (DHCP eth0/ens3)
mkdir -p /etc/netplan
cat >/etc/netplan/01-netcfg.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0: { dhcp4: true, optional: true }
    ens3: { dhcp4: true, optional: true }
EOF

# /etc/hosts & /etc/fstab
cat >/etc/hosts <<EOF
127.0.0.1 localhost
127.0.1.1 ubuntu20
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
: "\${ROOT_UUID:?}" "\${FSTYPE:?}"
cat >/etc/fstab <<EOF
UUID=${ROOT_UUID} / ${FSTYPE} defaults,errors=remount-ro 0 1
EOF

# Direktori & perms yang sering bikin installer error
chmod 1777 /tmp /var/tmp || true
install -d -m 755 /usr/local/bin /usr/local/etc /usr/local/etc/xray /usr/local/share/xray /var/log/xray

# ---------- BUKA SEMUA PORT (iptables ACCEPT, persist) ----------
apt-get install -y debconf-utils iptables iptables-persistent netfilter-persistent nftables
echo 'iptables-persistent iptables-persistent/autosave_v4 boolean true' | debconf-set-selections
echo 'iptables-persistent iptables-persistent/autosave_v6 boolean true' | debconf-set-selections

# Flush iptables v4/v6 & set default policy ACCEPT
iptables -P INPUT ACCEPT || true; iptables -P FORWARD ACCEPT || true; iptables -P OUTPUT ACCEPT || true
iptables -F || true; iptables -X || true; iptables -t nat -F || true; iptables -t mangle -F || true
ip6tables -P INPUT ACCEPT || true; ip6tables -P FORWARD ACCEPT || true; ip6tables -P OUTPUT ACCEPT || true
ip6tables -F || true; ip6tables -X || true; ip6tables -t nat -F || true; ip6tables -t mangle -F || true

# Simpan rules kosong (ACCEPT semua) agar persisten
install -d /etc/iptables
cat >/etc/iptables/rules.v4 <<'V4'
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
COMMIT
V4
cat >/etc/iptables/rules.v6 <<'V6'
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
COMMIT
V6
iptables-restore < /etc/iptables/rules.v4 || true
ip6tables-restore < /etc/iptables/rules.v6 || true
systemctl enable netfilter-persistent || true
netfilter-persistent save || true

# Nonaktifkan nftables & UFW
systemctl disable --now nftables || true
apt-get purge -y ufw || true  # kalau ada
# ---------- END buka semua port ----------

# Pasang GRUB non-interaktif
: "\${DISK_DEV:?}"
grub-install "${DISK_DEV}"
update-initramfs -u
update-grub
CHROOT

# ---------- Rsync root baru ke / (2-pass, tahan banting) ----------
echo "📝 Exclude untuk rsync…"
cat >/root/rsync-exclude.txt <<'EOF'
/dev/*
/proc/*
/sys/*
/run/*
/tmp/*
/mnt/ubuntu20/*
/media/*
/lost+found
/swapfile
EOF

echo "📦 Sync PASS-1 (dengan xattrs/ACL)…"
set +e
rsync -aAXH --numeric-ids --delete --one-file-system --super \
  --info=progress2 \
  --exclude-from=/root/rsync-exclude.txt \
  /mnt/ubuntu20/ / 2>/root/rsync-pass1.err
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
  echo "⚠️ rsync PASS-1 error ($RC). Jalankan PASS-2 fallback…"
  rsync -aH --numeric-ids --delete --one-file-system --super \
    --omit-dir-times --no-inc-recursive \
    --info=progress2 \
    --exclude-from=/root/rsync-exclude.txt \
    /mnt/ubuntu20/ / 2>/root/rsync-pass2.err
fi

sync
umount -l /mnt/ubuntu20/dev /mnt/ubuntu20/proc /mnt/ubuntu20/sys || true
echo "🔁 Reboot ke Ubuntu 20.04 baru…"
reboot

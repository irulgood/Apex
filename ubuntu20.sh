cat >/root/downgrade-onepass.sh <<'SH'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "🚨 AKAN MENGGANTI OS ke Ubuntu 20.04 (focal). Semua data lama HILANG."
read -p "Lanjut? (y/N): " ok
[[ "${ok}" != "y" ]] && echo "Batal." && exit 1

# ---------- helper ----------
wait_apt_clear() {
  echo "⏳ Menunggu & mematikan proses APT/dpkg…"
  systemctl stop apt-daily.service apt-daily-upgrade.service unattended-upgrades 2>/dev/null || true
  systemctl stop apt-daily.timer  apt-daily-upgrade.timer  2>/dev/null || true
  local t=0
  while pgrep -fa '(apt|apt-get|dpkg|apt.systemd.daily|unattended)' >/dev/null; do
    ((t++))
    if (( t % 5 == 0 )); then
      systemctl kill --kill-who=all apt-daily.service apt-daily-upgrade.service unattended-upgrades 2>/dev/null || true
      pkill -9 -x apt     2>/dev/null || true
      pkill -9 -x apt-get 2>/dev/null || true
      pkill -9 -x dpkg    2>/dev/null || true
      pkill -9 -f 'apt.systemd.daily|unattended' 2>/dev/null || true
    fi
    ((t>60)) && break
    sleep 2
  done
  rm -f /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock || true
  dpkg --configure -a || true
}
ensure_dev_null() { rm -f /dev/null || true; mknod -m 666 /dev/null c 1 3 || true; chown root:root /dev/null || true; }

# ---------- deteksi disk/partisi ----------
ROOT_PART="$(findmnt -no SOURCE /)"; [[ -z "$ROOT_PART" ]] && { echo "Gagal deteksi root partition"; exit 1; }
PKNAME="$(lsblk -no PKNAME "$ROOT_PART" || true)"; [[ -z "$PKNAME" ]] && PKNAME="$(basename "$ROOT_PART" | sed 's/[0-9]*$//')"
DISK_DEV="/dev/${PKNAME}"
FSTYPE="$(findmnt -no FSTYPE / || echo ext4)"
ROOT_UUID="$(blkid -s UUID -o value "$ROOT_PART" || true)"
echo "🧭 ROOT_PART=$ROOT_PART  DISK_DEV=$DISK_DEV  FSTYPE=$FSTYPE  UUID=$ROOT_UUID"

# ---------- host siap ----------
ensure_dev_null
wait_apt_clear
apt-get update
apt-get install -y debootstrap gdisk wget gpgv gnupg2 ca-certificates rsync

# ---------- bootstrap focal ----------
mkdir -p /mnt/ubuntu20
[[ -x /mnt/ubuntu20/bin/sh ]] || debootstrap focal /mnt/ubuntu20 http://archive.ubuntu.com/ubuntu

# ---------- bind mounts ----------
mountpoint -q /mnt/ubuntu20/dev  || mount --bind /dev  /mnt/ubuntu20/dev
mountpoint -q /mnt/ubuntu20/proc || mount --bind /proc /mnt/ubuntu20/proc
mountpoint -q /mnt/ubuntu20/sys  || mount --bind /sys  /mnt/ubuntu20/sys
cp /etc/resolv.conf /mnt/ubuntu20/etc/resolv.conf
rm -f /mnt/ubuntu20/dev/null || true; mknod -m 666 /mnt/ubuntu20/dev/null c 1 3 || true; chown root:root /mnt/ubuntu20/dev/null || true

# ---------- siapkan focal di chroot ----------
export DISK_DEV ROOT_UUID FSTYPE
chroot /mnt/ubuntu20 /bin/bash -eux <<'CHROOT'
export DEBIAN_FRONTEND=noninteractive

# Repo lengkap
cat >/etc/apt/sources.list <<'EOF'
deb http://archive.ubuntu.com/ubuntu focal main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu focal-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu focal-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu focal-security main restricted universe multiverse
EOF
apt-get update

# Paket inti OS
apt-get -o Dpkg::Options::="--force-overwrite" install -y \
  linux-image-generic-hwe-20.04 initramfs-tools \
  grub-pc grub-common \
  openssh-server sudo net-tools systemd-sysv netplan.io \
  ca-certificates curl wget gnupg xz-utils tar unzip iproute2 lsb-release \
  rsyslog cron logrotate iptables iptables-persistent netfilter-persistent nftables

# Hostname
echo "ubuntu20" > /etc/hostname

# SSH root + password
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || true
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
echo 'UsePAM yes' >> /etc/ssh/sshd_config
ssh-keygen -A
echo "root:@Irul21tun" | chpasswd
# enable ssh (offline symlink)
ln -sf /lib/systemd/system/ssh.service /etc/systemd/system/multi-user.target.wants/ssh.service

# Netplan (DHCP untuk semua NIC DigitalOcean: eth0/ens3/enp*)
mkdir -p /etc/netplan
cat >/etc/netplan/01-netcfg.yaml <<'YAML'
network:
  version: 2
  renderer: networkd
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "🚨 AKAN MENGGANTI OS ke Ubuntu 20.04 (focal). Semua data lama HILANG."
read -p "Lanjut? (y/N): " ok
[[ "${ok}" != "y" ]] && echo "Batal." && exit 1

wait_apt_clear() {
systemctl stop apt-daily.service apt-daily-upgrade.service unattended-upgrades 2>/dev/null || true
systemctl stop apt-daily.timer  apt-daily-upgrade.timer  2>/dev/null || true
local t=0
while pgrep -x apt >/dev/null || pgrep -x apt-get >/dev/null || pgrep -x dpkg >/dev/null; do
((t++)); [[ $t -gt 60 ]] && killall apt apt-get dpkg 2>/dev/null || true
sleep 2
done
rm -f /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock || true
dpkg --configure -a || true
}
ensure_dev_null() { rm -f /dev/null || true; mknod -m 666 /dev/null c 1 3 || true; chown root:root /dev/null || true; }

ROOT_PART="$(findmnt -no SOURCE /)"; [[ -z "$ROOT_PART" ]] && { echo "Gagal deteksi root partition"; exit 1; }
PKNAME="$(lsblk -no PKNAME "$ROOT_PART" || true)"; [[ -z "$PKNAME" ]] && PKNAME="$(basename "$ROOT_PART" | sed 's/[0-9]*$//')"
DISK_DEV="/dev/${PKNAME}"
FSTYPE="$(findmnt -no FSTYPE / || echo ext4)"
ROOT_UUID="$(blkid -s UUID -o value "$ROOT_PART" || true)"
echo "🧭 ROOT_PART=$ROOT_PART  DISK_DEV=$DISK_DEV  FSTYPE=$FSTYPE  UUID=$ROOT_UUID"

ensure_dev_null
wait_apt_clear

echo "🔧 Install tools (host)…"
apt-get update
apt-get install -y debootstrap gdisk wget gpgv gnupg2 ca-certificates rsync

echo "📁 Bootstrap focal ke /mnt/ubuntu20…"
mkdir -p /mnt/ubuntu20
[[ -x /mnt/ubuntu20/bin/sh ]] || debootstrap focal /mnt/ubuntu20 http://archive.ubuntu.com/ubuntu

echo "🔗 Bind mount chroot…"
mountpoint -q /mnt/ubuntu20/dev  || mount --bind /dev  /mnt/ubuntu20/dev
mountpoint -q /mnt/ubuntu20/proc || mount --bind /proc /mnt/ubuntu20/proc
mountpoint -q /mnt/ubuntu20/sys  || mount --bind /sys  /mnt/ubuntu20/sys
cp /etc/resolv.conf /mnt/ubuntu20/etc/resolv.conf
rm -f /mnt/ubuntu20/dev/null || true; mknod -m 666 /mnt/ubuntu20/dev/null c 1 3 || true; chown root:root /mnt/ubuntu20/dev/null || true

echo "🌐 Konfigurasi sistem baru (chroot)…"
export DISK_DEV ROOT_UUID FSTYPE
chroot /mnt/ubuntu20 /bin/bash -eux <<'CHROOT'
apt-get update
apt-get -o Dpkg::Options::="--force-overwrite" install -y \
linux-image-generic-hwe-20.04 initramfs-tools \
grub-pc grub-common openssh-server sudo net-tools systemd-sysv netplan.io
echo "ubuntu20" > /etc/hostname


# SSH root+password (regex diperbaiki)
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || true
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
echo 'UsePAM yes' >> /etc/ssh/sshd_config
ssh-keygen -A
echo "root:@Irul21tun" | chpasswd

# Netplan DHCP (match semua "e*": eth0/ens3/enp*)
mkdir -p /etc/netplan
cat >/etc/netplan/01-netcfg.yaml <<'YAML'
network:
  version: 2
  renderer: networkd
  ethernets:
    default:
      match:
        name: "e*"
      dhcp4: true
      optional: true
YAML

# Enable networkd/resolved/ssh secara offline (symlink)
ln -sf /lib/systemd/system/systemd-networkd.service \
      /etc/systemd/system/multi-user.target.wants/systemd-networkd.service
ln -sf /lib/systemd/system/systemd-resolved.service \
      /etc/systemd/system/multi-user.target.wants/systemd-resolved.service
ln -sf /lib/systemd/system/ssh.service \
      /etc/systemd/system/multi-user.target.wants/ssh.service

# resolv.conf via resolved; fallback DNS statik bila stub belum ada
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || \
  printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.cf


hosts & fstab

cat >/etc/hosts <<EOF
127.0.0.1 localhost
127.0.1.1 ubuntu20
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
  ethernets:
    default:
      match:
        name: "e*"
      dhcp4: true
      optional: true
YAML
# enable networkd & resolved offline (symlink)
ln -sf /lib/systemd/system/systemd-networkd.service  /etc/systemd/system/multi-user.target.wants/systemd-networkd.service
ln -sf /lib/systemd/system/systemd-resolved.service  /etc/systemd/system/multi-user.target.wants/systemd-resolved.service
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" >/etc/resolv.conf

# hosts & fstab (ROOT_UUID/FSTYPE dari env host)
: "${ROOT_UUID:?}" "${FSTYPE:?}"
cat >/etc/hosts <<'EOF'
127.0.0.1 localhost
127.0.1.1 ubuntu20
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
cat >/etc/fstab <<EOF
UUID=${ROOT_UUID} / ${FSTYPE} defaults,errors=remount-ro 0 1
EOF

# Fondasi FS & direktori Xray
chmod 1777 /tmp /var/tmp || true
install -d -m 755 /usr/local/bin /usr/local/etc /usr/local/etc/xray /usr/local/share/xray /var/log/xray
ln -sfn /usr/local/etc/xray /etc/xray

# Buka semua port (ACCEPT semua) + persist
echo 'iptables-persistent iptables-persistent/autosave_v4 boolean true' | debconf-set-selections
echo 'iptables-persistent iptables-persistent/autosave_v6 boolean true' | debconf-set-selections
iptables -P INPUT ACCEPT || true; iptables -P FORWARD ACCEPT || true; iptables -P OUTPUT ACCEPT || true
iptables -F || true; iptables -X || true; iptables -t nat -F || true; iptables -t mangle -F || true
ip6tables -P INPUT ACCEPT || true; ip6tables -P FORWARD ACCEPT || true; ip6tables -P OUTPUT ACCEPT || true
ip6tables -F || true; ip6tables -X || true; ip6tables -t nat -F || true; ip6tables -t mangle -F || true
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
systemctl disable --now nftables || true
apt-get purge -y ufw || true

# Pasang GRUB ke disk
: "${DISK_DEV:?}"
grub-install "${DISK_DEV}"
update-initramfs -u
update-grub

# ---------- First-boot Xray (detector & installer) ----------
cat >/etc/default/firstboot-xray <<'CFG'
XRAY_ENABLE=1
XRAY_PORT=443
XRAY_UUID=""
INSTALL_HAPROXY=0
CFG

cat >/root/firstboot-xray.sh <<'FB'
#!/bin/bash
set -euo pipefail
exec > >(tee -a /var/log/firstboot-xray.log) 2>&1
source /etc/default/firstboot-xray || true
: "${XRAY_ENABLE:=1}" "${XRAY_PORT:=443}" "${INSTALL_HAPROXY:=0}" "${XRAY_UUID:=}"
[[ "$XRAY_ENABLE" != "1" ]] && exit 0

rm -f /dev/null || true; mknod -m 666 /dev/null c 1 3 || true; chown root:root /dev/null || true
rm -f /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock || true
dpkg --configure -a || true
apt-get update
apt-get install -y ca-certificates curl unzip xz-utils iproute2
update-ca-certificates || true

if ! command -v xray >/dev/null 2>&1; then
  bash <(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh) || {
    VER="$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep -oP '"'"'tag_name":\s*"\K[^"]+')" || true
    wget -O /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${VER:-v1.8.10}/Xray-linux-64.zip"
    unzip -o /tmp/xray.zip -d /tmp/xray
    install -m755 /tmp/xray/xray /usr/local/bin/xray
    install -d /usr/local/share/xray
    install -m644 /tmp/xray/geoip.dat /usr/local/share/xray/geoip.dat
    install -m644 /tmp/xray/geosite.dat /usr/local/share/xray/geosite.dat
  }
fi

install -d -m 755 /usr/local/etc/xray
ln -sfn /usr/local/etc/xray /etc/xray

if [[ -z "${XRAY_UUID}" ]]; then XRAY_UUID="$(cat /proc/sys/kernel/random/uuid)"; fi
grep -q '^XRAY_UUID=' /etc/default/firstboot-xray 2>/dev/null && sed -i 's/^XRAY_UUID=.*/XRAY_UUID='"$XRAY_UUID"'/' /etc/default/firstboot-xray || echo "XRAY_UUID=${XRAY_UUID}" >> /etc/default/firstboot-xray

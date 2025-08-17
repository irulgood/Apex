#!/bin/bash
# ubuntu20.sh — Downgrade DO droplet ke Ubuntu 20.04 (focal) dengan guard anti-gagal
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

LOG="/root/downgrade-$(date +%F-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

info(){ echo -e "\e[36m$*\e[0m"; }
warn(){ echo -e "\e[33m$*\e[0m" >&2; }
die(){  echo -e "\e[31mERROR:\e[0m $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Harus dijalankan sebagai root"

info "🚨 Skrip ini AKAN MENGGANTI OS ke Ubuntu 20.04 (focal). Semua data lama HILANG."
read -p "Ketik 'YES' untuk lanjut: " OK
[[ "${OK:-}" == "YES" ]] || die "Dibatalkan."

# ---------- Helper: bereskan APT & device ----------
wait_apt_clear() {
  info "⏳ Stop otomatisasi APT & bersihkan lock…"
  systemctl stop apt-daily.service apt-daily-upgrade.service unattended-upgrades 2>/dev/null || true
  systemctl stop apt-daily.timer  apt-daily-upgrade.timer  2>/dev/null || true
  local i=0
  while pgrep -fa '(apt|apt-get|dpkg|apt.systemd.daily|unattended)' >/dev/null; do
    ((i++))
    if (( i % 5 == 0 )); then
      systemctl kill --kill-who=all apt-daily.service apt-daily-upgrade.service unattended-upgrades 2>/dev/null || true
      pkill -9 -x apt       2>/dev/null || true
      pkill -9 -x apt-get   2>/dev/null || true
      pkill -9 -x dpkg      2>/dev/null || true
      pkill -9 -f 'apt.systemd.daily|unattended|packagekit' 2>/dev/null || true
    fi
    (( i > 60 )) && break
    sleep 2
  done
  rm -f /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock || true
  dpkg --configure -a || true
}
fix_dev_null() { rm -f /dev/null || true; mknod -m 666 /dev/null c 1 3 || true; chown root:root /dev/null || true; }

# ---------- Deteksi disk/partisi ----------
ROOT_PART="$(findmnt -no SOURCE / || true)"; [ -n "$ROOT_PART" ] || die "Gagal deteksi root partition"
PKNAME="$(lsblk -no PKNAME "$ROOT_PART" 2>/dev/null || true)"; [ -n "$PKNAME" ] || PKNAME="$(basename "$ROOT_PART" | sed 's/[0-9]*$//')"
DISK_DEV="/dev/${PKNAME}"
FSTYPE="$(findmnt -no FSTYPE / || echo ext4)"
ROOT_UUID="$(blkid -s UUID -o value "$ROOT_PART" || true)"
info "🧭 ROOT_PART=$ROOT_PART  DISK_DEV=$DISK_DEV  FSTYPE=$FSTYPE  UUID=$ROOT_UUID"

# ---------- Host siap ----------
fix_dev_null
mount | grep ' on / ' | grep -q '(rw,' || mount -o remount,rw /
wait_apt_clear
info "🔧 Install tools (host)…"
apt-get update
apt-get install -y debootstrap rsync gnupg gpgv ca-certificates wget xz-utils tar

# ---------- Bootstrap focal ----------
info "📁 Bootstrap focal → /mnt/ubuntu20…"
mkdir -p /mnt/ubuntu20
if [[ ! -x /mnt/ubuntu20/bin/sh ]]; then
  debootstrap focal /mnt/ubuntu20 http://archive.ubuntu.com/ubuntu
else
  info "ℹ️  /mnt/ubuntu20 sudah ada — lewati debootstrap."
fi

# ---------- Bind mounts ----------
info "🔗 Bind mount chroot…"
mountpoint -q /mnt/ubuntu20/dev  || mount --bind /dev  /mnt/ubuntu20/dev
mountpoint -q /mnt/ubuntu20/proc || mount --bind /proc /mnt/ubuntu20/proc
mountpoint -q /mnt/ubuntu20/sys  || mount --bind /sys  /mnt/ubuntu20/sys
cp /etc/resolv.conf /mnt/ubuntu20/etc/resolv.conf || true
rm -f /mnt/ubuntu20/dev/null || true; mknod -m 666 /mnt/ubuntu20/dev/null c 1 3 || true; chown root:root /mnt/ubuntu20/dev/null || true

# ---------- CHROOT A: repo, paket inti (tanpa grub-pc), jaringan, ssh, firewall ----------
info "🌐 Konfigurasi sistem baru (CHROOT A)…"
chroot /mnt/ubuntu20 /bin/bash -eux <<'CHROOT_A'
export DEBIAN_FRONTEND=noninteractive

# Repo lengkap
cat >/etc/apt/sources.list <<'SL'
deb http://archive.ubuntu.com/ubuntu focal main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu focal-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu focal-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu focal-security main restricted universe multiverse
SL
apt-get update

# Paket inti (tanpa grub-pc dulu untuk cegah prompt), plus DHCP client & debconf-utils
apt-get -o Dpkg::Options::="--force-overwrite" install -y \
  linux-image-generic-hwe-20.04 initramfs-tools \
  grub-common \
  openssh-server sudo net-tools systemd-sysv netplan.io \
  ca-certificates curl wget gnupg xz-utils tar unzip iproute2 lsb-release \
  rsyslog cron logrotate iptables iptables-persistent netfilter-persistent nftables \
  isc-dhcp-client debconf-utils

update-ca-certificates || true
echo "ubuntu20" > /etc/hostname

# SSH root + password + enable offline
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || true
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
echo 'UsePAM yes' >> /etc/ssh/sshd_config
ssh-keygen -A
echo "root:@Irul21tun" | chpasswd
ln -sf /lib/systemd/system/ssh.service /etc/systemd/system/multi-user.target.wants/ssh.service

# Netplan DHCP (semua NIC awalan "e": eth0/ens3/enp*)
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

# Fallback DHCP: systemd-networkd native
mkdir -p /etc/systemd/network
cat >/etc/systemd/network/10-e-dhcp.network <<'NWT'
[Match]
Name=e*

[Network]
DHCP=ipv4

[DHCPv4]
UseDNS=yes
UseDomains=yes
RouteMetric=100
NWT

# Enable networkd & resolved offline
ln -sf /lib/systemd/system/systemd-networkd.service  /etc/systemd/system/multi-user.target.wants/systemd-networkd.service
ln -sf /lib/systemd/system/systemd-resolved.service  /etc/systemd/system/multi-user.target.wants/systemd-resolved.service
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || \
  printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' >/etc/resolv.conf

# /etc/hosts (fstab ditulis dari host)
cat >/etc/hosts <<'HST'
127.0.0.1 localhost
127.0.1.1 ubuntu20
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
HST

# Direktori standar Xray (opsional)
chmod 1777 /tmp /var/tmp || true
install -d -m 755 /usr/local/bin /usr/local/etc /usr/local/etc/xray /usr/local/share/xray /var/log/xray
ln -sfn /usr/local/etc/xray /etc/xray

# Firewall OS: buka semua port + persist
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

# Network guard: pastikan dapat IP & SSH start di boot
cat >/usr/local/sbin/boot-netfix.sh <<'BOOT'
#!/bin/bash
set -euo pipefail
sleep 3
HAS_IP=$(ip -4 -br addr show scope global | awk '$3!~/^$/ {c++} END{print c+0}')
HAS_GW=$(ip route show default | wc -l)
if [ "$HAS_IP" -eq 0 ] || [ "$HAS_GW" -eq 0 ]; then
  systemctl restart systemd-networkd || true
  netplan apply 2>/dev/null || true
  for P in /sys/class/net/e*; do
    [ -e "$P" ] || continue
    IF=$(basename "$P")
    ip link set "$IF" up || true
    timeout 20s dhclient -1 -v "$IF" || true
  done
fi
systemctl start ssh || true
exit 0
BOOT
chmod +x /usr/local/sbin/boot-netfix.sh

cat >/etc/systemd/system/firstboot-netfix.service <<'UNIT'
[Unit]
Description=Network guard to ensure DHCP on boot (DigitalOcean)
After=network-pre.target
Before=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/boot-netfix.sh

[Install]
WantedBy=multi-user.target
UNIT
ln -sf /etc/systemd/system/firstboot-netfix.service /etc/systemd/system/multi-user.target.wants/firstboot-netfix.service
CHROOT_A

# ---------- Tulis fstab dari host ----------
[ -n "$ROOT_UUID" ] || die "ROOT_UUID kosong"
cat >/mnt/ubuntu20/etc/fstab <<EOF_FSTAB
UUID=${ROOT_UUID} / ${FSTYPE} defaults,errors=remount-ro 0 1
EOF_FSTAB

# ---------- Preseed grub-pc & install ----------
info "🧩 Preseed & pasang GRUB…"
chroot /mnt/ubuntu20 /bin/bash -eux -c 'apt-get update && apt-get install -y debconf-utils'
chroot /mnt/ubuntu20 /bin/bash -eux -c "echo 'grub-pc grub-pc/install_devices multiselect ${DISK_DEV}' | debconf-set-selections"
chroot /mnt/ubuntu20 /bin/bash -eux -c "echo 'grub-pc grub-pc/install_devices_empty boolean false' | debconf-set-selections"
chroot /mnt/ubuntu20 /bin/bash -eux -c "echo 'grub-pc grub2/linux_cmdline string net.ifnames=0 biosdevname=0' | debconf-set-selections"
chroot /mnt/ubuntu20 /bin/bash -eux -c 'DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-overwrite" install grub-pc grub-common'
# Pastikan GRUB cmdline konsisten
chroot /mnt/ubuntu20 /bin/bash -eux -c 'if grep -q "^GRUB_CMDLINE_LINUX=" /etc/default/grub; then sed -i "s/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"net.ifnames=0 biosdevname=0\"/" /etc/default/grub; else echo "GRUB_CMDLINE_LINUX=\"net.ifnames=0 biosdevname=0\"" >> /etc/default/grub; fi'
# Install ke disk & regen initramfs/grub.cfg
chroot /mnt/ubuntu20 /bin/bash -eux -c "grub-install ${DISK_DEV} && update-initramfs -u && update-grub"

# ---------- Siapkan exclude & lepas snap agar rsync bersih ----------
info "🧹 Siapkan exclude & lepas snap…"
systemctl stop snapd 2>/dev/null || true
systemctl disable --now snapd 2>/dev/null || true
# Unmount semua mount di /snap agar tidak 'non-empty'
for M in $(mount | awk '/ \/snap\//{print $3}'); do umount -l "$M" || true; done
umount -l /snap 2>/dev/null || true

cat >/root/rsync-exclude.txt <<'EXC'
/dev/*
/proc/*
/sys/*
/run/*
/tmp/*
/mnt/ubuntu20/*
/mnt/ubuntu20
/media/*
/lost+found
/swapfile
/snap/*
/var/snap/*
/var/lib/snapd/*
EXC

# ---------- Rsync 2-pass ----------
info "📦 Sync root baru → / (PASS-1)… (SSH bisa putus setelah tahap ini)"
set +e
rsync -aAXH --numeric-ids --delete --one-file-system --super \
  --info=progress2 \
  --exclude-from=/root/rsync-exclude.txt \
  /mnt/ubuntu20/ / 2>/root/rsync-pass1.err
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
  warn "⚠️ PASS-1 error ($RC). PASS-2 fallback…"
  rsync -aH --numeric-ids --delete --one-file-system --super \
    --omit-dir-times --no-inc-recursive \
    --info=progress2 \
    --exclude-from=/root/rsync-exclude.txt \
    /mnt/ubuntu20/ / 2>/root/rsync-pass2.err
fi

sync
umount -l /mnt/ubuntu20/dev /mnt/ubuntu20/proc /mnt/ubuntu20/sys || true
info "🔁 Reboot ke Ubuntu 20.04…"
systemctl reboot || reboot || reboot -f

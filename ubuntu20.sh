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

SSH root+password

sed -i 's/^#?PermitRootLogin./PermitRootLogin yes/' /etc/ssh/sshd_config || true
sed -i 's/^#?PasswordAuthentication./PasswordAuthentication yes/' /etc/ssh/sshd_config || true
echo 'UsePAM yes' >> /etc/ssh/sshd_config
ssh-keygen -A
echo "root:@Irul21tun" | chpasswd

Netplan DHCP (eth0/ens3)

mkdir -p /etc/netplan
cat >/etc/netplan/01-netcfg.yaml <<EOF
network:
version: 2
renderer: networkd
ethernets:
eth0: { dhcp4: true, optional: true }
ens3: { dhcp4: true, optional: true }
EOF

hosts & fstab

cat >/etc/hosts <<EOF
127.0.0.1 localhost
127.0.1.1 ubuntu20
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
: "${ROOT_UUID:?}" "${FSTYPE:?}"
cat >/etc/fstab <<EOF
UUID=${ROOT_UUID} / ${FSTYPE} defaults,errors=remount-ro 0 1
EOF

GRUB

: "${DISK_DEV:?}"
grub-install "${DISK_DEV}"
update-initramfs -u
update-grub
CHROOT

echo "📝 Exclude list rsync…"
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

echo "📦 Sync root baru ke / (PASS-1)…"
set +e
rsync -aAXH --numeric-ids --delete --one-file-system --super \
--info=progress2 \
--exclude-from=/root/rsync-exclude.txt \
/mnt/ubuntu20/ / 2>/root/rsync-pass1.err
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
echo "⚠️ rsync PASS-1 error ($RC). Menjalankan PASS-2 (fallback)…"
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

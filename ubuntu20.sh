#!/bin/bash
set -euo pipefail

echo "🚨 AKAN MENGGANTI OS ke Ubuntu 20.04 (focal). Semua data lama HILANG."
read -p "Lanjut? (y/N): " ok
[[ "${ok}" != "y" ]] && echo "Batal." && exit 1

# ---------- Detect disk/partition ----------
ROOT_PART="$(findmnt -no SOURCE /)"
if [[ -z "${ROOT_PART}" ]]; then echo "Gagal deteksi root partition"; exit 1; fi
PKNAME="$(lsblk -no PKNAME "${ROOT_PART}" || true)"
if [[ -z "${PKNAME}" ]]; then PKNAME="$(basename "${ROOT_PART}" | sed 's/[0-9]*$//')"; fi
DISK_DEV="/dev/${PKNAME}"
FSTYPE="$(findmnt -no FSTYPE / || echo ext4)"
ROOT_UUID="$(blkid -s UUID -o value "${ROOT_PART}" || true)"

echo "🧭 ROOT_PART=${ROOT_PART}  DISK_DEV=${DISK_DEV}  FSTYPE=${FSTYPE}  UUID=${ROOT_UUID}"

# ---------- Fix /dev/null (host) ----------
rm -f /dev/null || true
mknod -m 0666 /dev/null c 1 3 || true
chown root:root /dev/null || true

echo "🔧 Install tools (host)..."
apt-get update
apt-get install -y debootstrap gdisk wget gpgv gnupg2 ca-certificates rsync

echo "📁 Bootstrap Ubuntu 20.04 ke /mnt/ubuntu20..."
mkdir -p /mnt/ubuntu20
debootstrap focal /mnt/ubuntu20 http://archive.ubuntu.com/ubuntu

echo "🔗 Bind-mount untuk chroot..."
mount --bind /dev  /mnt/ubuntu20/dev
mount --bind /proc /mnt/ubuntu20/proc
mount --bind /sys  /mnt/ubuntu20/sys
cp /etc/resolv.conf /mnt/ubuntu20/etc/resolv.conf

# Fix /dev/null di target
rm -f /mnt/ubuntu20/dev/null || true
mknod -m 0666 /mnt/ubuntu20/dev/null c 1 3 || true
chown root:root /mnt/ubuntu20/dev/null || true

echo "🌐 Konfig & install paket inti di sistem baru (chroot)..."
export DISK_DEV ROOT_UUID FSTYPE
chroot /mnt/ubuntu20 /bin/bash -eux <<'CHROOT'
export DEBIAN_FRONTEND=noninteractive

# Update index
apt-get update

# Paket inti: kernel HWE 5.15, grub, ssh, initramfs, netplan, util
apt-get -o Dpkg::Options::="--force-overwrite" install -y \
  linux-image-generic-hwe-20.04 \
  initramfs-tools grub-pc grub-common \
  openssh-server sudo net-tools systemd-sysv netplan.io

# Hostname
echo "ubuntu20" > /etc/hostname

# SSH: izinkan root + password
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || true
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
echo 'UsePAM yes' >> /etc/ssh/sshd_config
ssh-keygen -A
echo "root:@Irul21tun" | chpasswd

# Netplan DHCP (eth0 & ens3, yang tidak ada akan diabaikan)
mkdir -p /etc/netplan
cat >/etc/netplan/01-netcfg.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0: { dhcp4: true, optional: true }
    ens3: { dhcp4: true, optional: true }
EOF

# /etc/hosts minimal
cat >/etc/hosts <<EOF
127.0.0.1 localhost
127.0.1.1 ubuntu20
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

# /etc/fstab untuk root
: "${ROOT_UUID:?}" "${FSTYPE:?}"
cat >/etc/fstab <<EOF
UUID=${ROOT_UUID} / ${FSTYPE} defaults,errors=remount-ro 0 1
EOF

# Pasang GRUB ke disk (noninteraktif)
: "${DISK_DEV:?}"
grub-install "${DISK_DEV}"
update-initramfs -u
update-grub
CHROOT

echo "📦 Salin sistem baru ke root (/), hapus sisa lama (overlay with delete)..."
rsync -aAXH --numeric-ids --delete \
  --exclude="/dev/*" --exclude="/proc/*" --exclude="/sys/*" \
  --exclude="/run/*" --exclude="/tmp/*" \
  --exclude="/mnt/ubuntu20/*" --exclude="/media/*" --exclude="/lost+found" \
  /mnt/ubuntu20/ /

echo "🧹 Unmount bind..."
umount -l /mnt/ubuntu20/dev /mnt/ubuntu20/proc /mnt/ubuntu20/sys || true

echo "🔁 Reboot ke Ubuntu 20.04 baru..."
reboot

set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# 0) Pastikan target root ada; kalau belum, bootstrap focal sekali
mkdir -p /mnt/ubuntu20
if [ ! -x /mnt/ubuntu20/bin/sh ]; then
  apt-get update
  apt-get install -y debootstrap gnupg ca-certificates
  debootstrap focal /mnt/ubuntu20 http://archive.ubuntu.com/ubuntu
fi

# 1) Bind-mount & resolv + perbaiki /dev/null di target
mountpoint -q /mnt/ubuntu20/dev  || mount --bind /dev  /mnt/ubuntu20/dev
mountpoint -q /mnt/ubuntu20/proc || mount --bind /proc /mnt/ubuntu20/proc
mountpoint -q /mnt/ubuntu20/sys  || mount --bind /sys  /mnt/ubuntu20/sys
cp /etc/resolv.conf /mnt/ubuntu20/etc/resolv.conf
rm -f /mnt/ubuntu20/dev/null || true; mknod -m 666 /mnt/ubuntu20/dev/null c 1 3; chown root:root /mnt/ubuntu20/dev/null

# 2) Siapkan focal di dalam chroot (repo lengkap, DHCP DO via match "e*", SSH, GRUB)
DISK_DEV="/dev/$(lsblk -no PKNAME "$(findmnt -no SOURCE /)")"
ROOT_UUID="$(blkid -s UUID -o value "$(findmnt -no SOURCE /)")"
FSTYPE="$(findmnt -no FSTYPE / || echo ext4)"

chroot /mnt/ubuntu20 /bin/bash -eux <<'CHROOT'
export DEBIAN_FRONTEND=noninteractive
cat >/etc/apt/sources.list <<EOF
deb http://archive.ubuntu.com/ubuntu focal main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu focal-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu focal-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu focal-security main restricted universe multiverse
EOF
apt-get update
apt-get -o Dpkg::Options::="--force-overwrite" install -y \
  linux-image-generic-hwe-20.04 initramfs-tools grub-pc grub-common \
  openssh-server sudo net-tools systemd-sysv netplan.io \
  ca-certificates curl wget gnupg xz-utils tar unzip iproute2 lsb-release

echo ubuntu20 >/etc/hostname

# SSH root+password
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
ssh-keygen -A
echo "root:@Irul21tun" | chpasswd

# Netplan: DHCP untuk semua NIC DigitalOcean (eth0/ens3/enp*)
mkdir -p /etc/netplan
cat >/etc/netplan/01-netcfg.yaml <<YAML
network:
  version: 2
  renderer: networkd
  ethernets:
    default:
      match: { name: "e*" }
      dhcp4: true
      optional: true
YAML
# enable networkd/resolved/ssh (offline symlink, aman di chroot)
ln -sf /lib/systemd/system/systemd-networkd.service /etc/systemd/system/multi-user.target.wants/systemd-networkd.service
ln -sf /lib/systemd/system/systemd-resolved.service /etc/systemd/system/multi-user.target.wants/systemd-resolved.service
ln -sf /lib/systemd/system/ssh.service /etc/systemd/system/multi-user.target.wants/ssh.service
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" >/etc/resolv.conf

# hosts & fstab (diisi oleh host lewat env)
CHROOT

# 3) Tuliskan fstab di chroot (pakai UUID root kamu sekarang)
cat >/mnt/ubuntu20/etc/fstab <<EOF
UUID=${ROOT_UUID} / ${FSTYPE} defaults,errors=remount-ro 0 1
EOF

# 4) Pasang GRUB ke disk utama dari chroot
chroot /mnt/ubuntu20 /bin/bash -eux <<CHROOT
grub-install "${DISK_DEV}"
update-initramfs -u
update-grub
CHROOT

# 5) Exclude untuk rsync dan lakukan sinkronisasi 2-pass
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

set +e
rsync -aAXH --numeric-ids --delete --one-file-system --super \
  --info=progress2 \
  --exclude-from=/root/rsync-exclude.txt \
  /mnt/ubuntu20/ / 2>/root/rsync-pass1.err
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
  rsync -aH --numeric-ids --delete --one-file-system --super \
    --omit-dir-times --no-inc-recursive \
    --info=progress2 \
    --exclude-from=/root/rsync-exclude.txt \
    /mnt/ubuntu20/ / 2>/root/rsync-pass2.err
fi

sync
umount -l /mnt/ubuntu20/dev /mnt/ubuntu20/proc /mnt/ubuntu20/sys || true
reboot

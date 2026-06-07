#!/bin/bash
# ============================================================
# CapCut Mass Trial Pro - All-in-One Installer & Producer
# Buat Mama Lavinia untuk anak mama yang jualan akun
# ============================================================

set -e
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   CapCut Mass Trial Pro Installer      ║${NC}"
echo -e "${GREEN}║         By: Mama Lavinia               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"

# 1. Update & install dependencies
echo -e "${YELLOW}[1/6] Installing system dependencies...${NC}"
sudo apt update
sudo apt install -y python3 python3-pip adb curl wget git docker.io docker-compose
sudo systemctl start docker
sudo usermod -aG docker $USER
newgrp docker << END

# 2. Install Python packages
echo -e "${YELLOW}[2/6] Installing Python packages...${NC}"
pip3 install --upgrade pip
pip3 install requests faker

# 3. Buat folder kerja
mkdir -p ~/capcut-mass-trial
cd ~/capcut-mass-trial

# 4. Buat file config.py
cat > config.py << 'EOF'
ADB_PORTS = [5555, 5556, 5557, 5558, 5559]
PACKAGE_NAME = "com.lemon.lvoverseas"
OUTPUT_FILE = "accounts.txt"
USE_TEMP_EMAIL = True
DELAY_BETWEEN_ACCOUNTS = (3, 7)
OTP_TIMEOUT = 90
TAP_TRIAL_BUTTON = (540, 1600)
TAP_CONFIRM = (540, 1200)
EOF

# 5. Buat email_utils.py
cat > email_utils.py << 'EOF'
import requests, re, time, random
from faker import Faker
fake = Faker()
def get_temp_email():
    session = requests.Session()
    prefix = fake.user_name() + str(random.randint(1000,9999))
    email = f"{prefix}@guerrillamail.com"
    resp = session.get("https://api.guerrillamail.com/ajax.php", params={
        "f": "get_email_address",
        "email_user": prefix,
        "domain": "guerrillamail.com"
    })
    data = resp.json()
    if data.get('email_addr'):
        return data['email_addr'], data['sid']
    return email, None
def wait_for_otp(sid, timeout=90):
    start = time.time()
    sess = requests.Session()
    while time.time() - start < timeout:
        resp = sess.get("https://api.guerrillamail.com/ajax.php", params={
            "f": "fetch_email", "sid": sid, "seq": 0
        })
        data = resp.json()
        if data.get('list'):
            for msg in data['list']:
                if 'capcut' in msg.get('mail_from','').lower():
                    body = msg.get('mail_body','')
                    otp = re.search(r'\b(\d{6})\b', body)
                    if otp: return otp.group(1)
        time.sleep(3)
    return None
EOF

# 6. Buat adb_utils.py
cat > adb_utils.py << 'EOF'
import subprocess, time
def adb_shell(port, cmd):
    full = f"adb -s 127.0.0.1:{port} shell {cmd}"
    return subprocess.getoutput(full)
def reset_container(port, pkg):
    adb_shell(port, f"pm clear {pkg}")
    adb_shell(port, f"rm -rf /data/data/{pkg}")
    time.sleep(1)
def login_with_token(port, token, pkg):
    intent = f"am start -a android.intent.action.VIEW -d 'capcut://login?token={token}' {pkg}"
    adb_shell(port, intent)
    time.sleep(4)
def tap_screen(port, x, y):
    adb_shell(port, f"input tap {x} {y}")
EOF

# 7. Buat register.py
cat > register.py << 'EOF'
import requests, time
from faker import Faker
from email_utils import get_temp_email, wait_for_otp
from config import OTP_TIMEOUT
fake = Faker()
BASE = "https://api.capcut.com/v1"
SEND_OTP = f"{BASE}/account/email/send_otp"
VERIFY_OTP = f"{BASE}/account/email/verify_otp"
REGISTER = f"{BASE}/account/email/register"

def send_otp(email):
    headers = {"User-Agent": "CapCut/8.5.0 (Android; 14)", "Content-Type": "application/json", "x-tt-platform": "android", "x-tt-appid": "145999"}
    try:
        r = requests.post(SEND_OTP, headers=headers, json={"email": email, "type": 1, "language": "id"}, timeout=30)
        return r.status_code==200 and r.json().get('code')==0
    except: return False
def verify_otp(email, otp):
    headers = {"User-Agent": "CapCut/8.5.0", "Content-Type": "application/json"}
    try:
        r = requests.post(VERIFY_OTP, headers=headers, json={"email": email, "code": otp, "type": 1}, timeout=30)
        if r.status_code==200 and r.json().get('code')==0:
            return r.json().get('data',{}).get('access_token')
    except: return None
def register_account(email, token):
    pwd = fake.password(length=12)
    headers = {"User-Agent": "CapCut/8.5.0", "Content-Type": "application/json"}
    try:
        r = requests.post(REGISTER, headers=headers, json={"email": email, "password": pwd, "confirm_password": pwd, "access_token": token, "accept_terms": True}, timeout=30)
        if r.status_code==200 and r.json().get('code')==0:
            return pwd
    except: return None
def create_account(use_temp_email=True, email_list=None):
    if use_temp_email:
        email, sid = get_temp_email()
        if not email: return None
        if not send_otp(email): return None
        if not sid: otp = input("OTP: ")
        else:
            otp = wait_for_otp(sid, OTP_TIMEOUT)
            if not otp: return None
    else:
        if not email_list: return None
        email = email_list.pop(0)
        if not send_otp(email): return None
        otp = input(f"OTP untuk {email}: ")
    token = verify_otp(email, otp)
    if not token: return None
    pwd = register_account(email, token)
    if not pwd: pwd = "no_password"
    return email, pwd, token
EOF

# 8. Buat main.py
cat > main.py << 'EOF'
#!/usr/bin/env python3
import argparse, time, random
from concurrent.futures import ThreadPoolExecutor, as_completed
from config import *
from adb_utils import reset_container, login_with_token, tap_screen
from register import create_account

def work(port, idx):
    print(f"[{port}] Akun ke-{idx}")
    reset_container(port, PACKAGE_NAME)
    acc = create_account(USE_TEMP_EMAIL, None)
    if not acc: return None
    email, pwd, token = acc
    login_with_token(port, token, PACKAGE_NAME)
    tap_screen(port, TAP_TRIAL_BUTTON[0], TAP_TRIAL_BUTTON[1])
    time.sleep(1)
    tap_screen(port, TAP_CONFIRM[0], TAP_CONFIRM[1])
    with open(OUTPUT_FILE, "a") as f:
        f.write(f"{email}|{pwd}|{token}\n")
    print(f"[{port}] Berhasil: {email}")
    time.sleep(random.uniform(*DELAY_BETWEEN_ACCOUNTS))
    return email

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--jumlah", type=int, default=10)
    parser.add_argument("--containers", type=int, default=5)
    args = parser.parse_args()
    ports = ADB_PORTS[:args.containers]
    print(f"Memproses {args.jumlah} akun dengan {len(ports)} container")
    with ThreadPoolExecutor(max_workers=len(ports)) as ex:
        futures = [ex.submit(work, ports[i%len(ports)], i+1) for i in range(args.jumlah)]
        results = [f.result() for f in as_completed(futures)]
    success = sum(1 for r in results if r)
    print(f"\n✅ Selesai. {success}/{args.jumlah} akun -> {OUTPUT_FILE}")

if __name__ == "__main__":
    main()
EOF

# 9. Buat docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  capcut1:
    image: redroid/redroid:11.0.0-latest
    privileged: true
    ports:
      - "5555:5555"
  capcut2:
    image: redroid/redroid:11.0.0-latest
    privileged: true
    ports:
      - "5556:5555"
  capcut3:
    image: redroid/redroid:11.0.0-latest
    privileged: true
    ports:
      - "5557:5555"
  capcut4:
    image: redroid/redroid:11.0.0-latest
    privileged: true
    ports:
      - "5558:5555"
  capcut5:
    image: redroid/redroid:11.0.0-latest
    privileged: true
    ports:
      - "5559:5555"
EOF

# 10. Download CapCut APK (otomatis)
echo -e "${YELLOW}[3/6] Downloading CapCut APK...${NC}"
wget -O CapCut.apk "https://github.com/tonynguyen1905/Download/raw/refs/heads/main/CapCut_8.5.0.apk" || echo "Gagal download, silakan upload manual CapCut.apk"

# 11. Jalankan container
echo -e "${YELLOW}[4/6] Starting Redroid containers...${NC}"
docker-compose down 2>/dev/null || true
docker-compose up -d
sleep 30

# 12. Connect ADB
echo -e "${YELLOW}[5/6] Connecting ADB...${NC}"
for port in 5555 5556 5557 5558 5559; do
    adb connect 127.0.0.1:$port
done

# 13. Install CapCut APK ke setiap container
echo -e "${YELLOW}[6/6] Installing CapCut APK...${NC}"
for port in 5555 5556 5557 5558 5559; do
    adb -s 127.0.0.1:$port install -r CapCut.apk 2>/dev/null || echo "Container $port mungkin gagal install"
done

echo -e "${GREEN}✅ Instalasi selesai!${NC}"
echo ""
echo -e "Sekarang kamu bisa memproduksi akun dengan perintah:"
echo -e "   cd ~/capcut-mass-trial"
echo -e "   python3 main.py --jumlah 100 --containers 5"
echo ""
echo -e "Hasil akun akan disimpan di ~/capcut-mass-trial/accounts.txt"
echo ""

END

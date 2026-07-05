#!/bin/bash
# ============================================================
#  RHF ZERO - OPERATOR PANEL (Termux CLI)
#  Menu: 1. Alamat Web  2. Akun  3. Generate Code
# ============================================================

# ---------- CONFIG ----------
# Config sensitif (Firebase key, DB URL) DIPISAH ke file config.sh
# supaya script ini aman di-upload ke repo GitHub publik.
CONFIG_FILE="$(dirname "$0")/config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "File config.sh tidak ditemukan."
  echo "Buat file config.sh di folder yang sama berisi:"
  echo ""
  echo '  FIREBASE_WEB_API_KEY="isi_key_di_sini"'
  echo '  DB_URL="isi_url_database_di_sini"'
  echo '  WEB_ADDRESS="isi_alamat_web_di_sini"'
  echo ""
  echo "Minta file config.sh ke admin/pemilik proyek."
  exit 1
fi

source "$CONFIG_FILE"

if [ -z "$FIREBASE_WEB_API_KEY" ] || [ -z "$DB_URL" ]; then
  echo "config.sh tidak lengkap. Pastikan FIREBASE_WEB_API_KEY dan DB_URL terisi."
  exit 1
fi

SESSION_FILE="$HOME/.rhfzero_session"   # menyimpan idToken + email hasil login (lokal saja, bukan di Firebase)

# ---------- CEK DEPENDENSI ----------
check_deps() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq belum terinstall. Menginstall otomatis..."
    pkg install -y jq >/dev/null 2>&1 || apt install -y jq >/dev/null 2>&1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl tidak ditemukan. Install dengan: pkg install curl"
    exit 1
  fi
}

# ---------- WARNA ----------
G='\033[0;32m'; R='\033[0;31m'; Y='\033[0;33m'; C='\033[0;36m'; NC='\033[0m'

pause(){ echo ""; read -p "Tekan ENTER untuk kembali ke menu..." _; }

# ---------- CEK SESI LOGIN ----------
is_logged_in() {
  [ -f "$SESSION_FILE" ] && [ -n "$(cat "$SESSION_FILE" 2>/dev/null | jq -r '.idToken // empty' 2>/dev/null)" ]
}

get_session_email() {
  jq -r '.email // "-"' "$SESSION_FILE" 2>/dev/null
}

get_session_name() {
  jq -r '.displayName // "-"' "$SESSION_FILE" 2>/dev/null
}

get_id_token() {
  jq -r '.idToken // empty' "$SESSION_FILE" 2>/dev/null
}

get_local_id() {
  jq -r '.localId // empty' "$SESSION_FILE" 2>/dev/null
}

# ============================================================
# MENU 1: ALAMAT WEB
# ============================================================
menu_web_address() {
  clear
  echo -e "${C}=== ALAMAT WEB RHF ZERO ===${NC}"
  echo ""
  echo -e "Website resmi bisa diakses di:"
  echo -e "${G}${WEB_ADDRESS}${NC}"
  echo ""
  echo "Bagikan alamat ini ke user yang butuh akses."
  pause
}

# ============================================================
# MENU 2: AKUN (daftar / login / ganti email & password)
# ============================================================
menu_akun() {
  while true; do
    clear
    echo -e "${C}=== AKUN ===${NC}"
    if is_logged_in; then
      echo -e "Status: ${G}LOGIN sebagai $(get_session_email)${NC}"
    else
      echo -e "Status: ${R}Belum login${NC}"
    fi
    echo ""
    echo "1. Daftar akun baru"
    echo "2. Login"
    echo "3. Ganti email / password (perlu verifikasi email lama)"
    echo "4. Logout"
    echo "0. Kembali ke menu utama"
    echo ""
    read -p "Pilih: " opt
    case $opt in
      1) akun_daftar ;;
      2) akun_login ;;
      3) akun_ganti_kredensial ;;
      4) akun_logout ;;
      0) break ;;
      *) echo -e "${R}Pilihan tidak valid.${NC}"; sleep 1 ;;
    esac
  done
}

akun_daftar() {
  clear
  echo -e "${C}--- DAFTAR AKUN BARU ---${NC}"
  read -p "Nama: " nama
  read -p "Email: " email
  read -sp "Password (min 6 karakter): " pass
  echo ""
  read -sp "Ulangi password: " pass2
  echo ""

  if [ -z "$nama" ]; then
    echo -e "${R}Nama tidak boleh kosong.${NC}"; pause; return
  fi
  if [ "$pass" != "$pass2" ]; then
    echo -e "${R}Password tidak sama.${NC}"; pause; return
  fi
  if [ ${#pass} -lt 6 ]; then
    echo -e "${R}Password minimal 6 karakter.${NC}"; pause; return
  fi

  resp=$(curl -s -X POST \
    "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${FIREBASE_WEB_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${email}\",\"password\":\"${pass}\",\"returnSecureToken\":true}")

  error_msg=$(echo "$resp" | jq -r '.error.message // empty')
  if [ -n "$error_msg" ]; then
    echo -e "${R}Gagal daftar: ${error_msg}${NC}"
    pause; return
  fi

  id_token=$(echo "$resp" | jq -r '.idToken')

  # Set displayName (nama) di profil Firebase Auth
  curl -s -X POST \
    "https://identitytoolkit.googleapis.com/v1/accounts:update?key=${FIREBASE_WEB_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"idToken\":\"${id_token}\",\"displayName\":\"${nama}\",\"returnSecureToken\":true}" > /dev/null

  echo "$resp" | jq --arg nama "$nama" '. + {displayName: $nama} | {idToken, email, localId, refreshToken, displayName}' > "$SESSION_FILE"
  echo -e "${G}Akun berhasil dibuat. Selamat datang, ${nama}!${NC}"
  pause
}

akun_login() {
  clear
  echo -e "${C}--- LOGIN AKUN ---${NC}"
  read -p "Email: " email
  read -sp "Password: " pass
  echo ""

  resp=$(curl -s -X POST \
    "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_WEB_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${email}\",\"password\":\"${pass}\",\"returnSecureToken\":true}")

  error_msg=$(echo "$resp" | jq -r '.error.message // empty')
  if [ -n "$error_msg" ]; then
    echo -e "${R}Login gagal: ${error_msg}${NC}"
    pause; return
  fi

  echo "$resp" | jq "{idToken, email, localId, refreshToken}" > "$SESSION_FILE"
  echo -e "${G}Login berhasil sebagai ${email}${NC}"
  pause
}

akun_logout() {
  rm -f "$SESSION_FILE"
  echo -e "${Y}Sesi lokal dihapus. Anda sudah logout.${NC}"
  pause
}

akun_ganti_kredensial() {
  clear
  echo -e "${C}--- GANTI EMAIL / PASSWORD ---${NC}"

  if ! is_logged_in; then
    echo -e "${R}Anda harus login dulu sebelum mengganti email/password.${NC}"
    pause; return
  fi

  current_email=$(get_session_email)
  echo "Akun saat ini: $current_email"
  echo ""
  echo -e "${Y}Verifikasi diperlukan: masukkan EMAIL LAMA untuk melanjutkan.${NC}"
  read -p "Konfirmasi email lama: " confirm_email

  if [ "$confirm_email" != "$current_email" ]; then
    echo -e "${R}Email lama tidak cocok. Perubahan dibatalkan.${NC}"
    pause; return
  fi

  # Re-verify identity with current password before allowing any change (extra safety layer)
  read -sp "Masukkan password saat ini untuk verifikasi: " verify_pass
  echo ""
  verify_resp=$(curl -s -X POST \
    "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_WEB_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${current_email}\",\"password\":\"${verify_pass}\",\"returnSecureToken\":true}")

  verify_error=$(echo "$verify_resp" | jq -r '.error.message // empty')
  if [ -n "$verify_error" ]; then
    echo -e "${R}Verifikasi gagal: password salah.${NC}"
    pause; return
  fi

  id_token=$(echo "$verify_resp" | jq -r '.idToken')

  echo ""
  echo "1. Ganti email"
  echo "2. Ganti password"
  read -p "Pilih: " sub_opt

  if [ "$sub_opt" = "1" ]; then
    read -p "Email baru: " new_email
    resp=$(curl -s -X POST \
      "https://identitytoolkit.googleapis.com/v1/accounts:update?key=${FIREBASE_WEB_API_KEY}" \
      -H "Content-Type: application/json" \
      -d "{\"idToken\":\"${id_token}\",\"email\":\"${new_email}\",\"returnSecureToken\":true}")

    err=$(echo "$resp" | jq -r '.error.message // empty')
    if [ -n "$err" ]; then
      echo -e "${R}Gagal ganti email: ${err}${NC}"
    else
      echo "$resp" | jq "{idToken, email, localId, refreshToken}" > "$SESSION_FILE"
      echo -e "${G}Email berhasil diganti menjadi ${new_email}${NC}"
    fi

  elif [ "$sub_opt" = "2" ]; then
    read -sp "Password baru (min 6 karakter): " new_pass
    echo ""
    if [ ${#new_pass} -lt 6 ]; then
      echo -e "${R}Password minimal 6 karakter.${NC}"; pause; return
    fi
    resp=$(curl -s -X POST \
      "https://identitytoolkit.googleapis.com/v1/accounts:update?key=${FIREBASE_WEB_API_KEY}" \
      -H "Content-Type: application/json" \
      -d "{\"idToken\":\"${id_token}\",\"password\":\"${new_pass}\",\"returnSecureToken\":true}")

    err=$(echo "$resp" | jq -r '.error.message // empty')
    if [ -n "$err" ]; then
      echo -e "${R}Gagal ganti password: ${err}${NC}"
    else
      echo "$resp" | jq "{idToken, email, localId, refreshToken}" > "$SESSION_FILE"
      echo -e "${G}Password berhasil diganti.${NC}"
    fi
  else
    echo -e "${R}Pilihan tidak valid.${NC}"
  fi
  pause
}

# ============================================================
# MENU 3: GENERATE CODE
# ============================================================
menu_generate_code() {
  clear
  echo -e "${C}=== GENERATE CODE AKSES ===${NC}"

  if ! is_logged_in; then
    echo -e "${R}Anda harus login akun dulu (Menu 2) sebelum bisa generate code.${NC}"
    pause; return
  fi

  echo "Login sebagai: $(get_session_email)"
  echo ""
  read -p "Kode berlaku berapa jam? (default 24): " hours
  hours=${hours:-24}

  code=$(head -c 32 /dev/urandom | tr -dc 'A-Z0-9' | head -c 32)
  now_ms=$(($(date +%s) * 1000))
  expires_ms=$((now_ms + hours * 3600 * 1000))
  local_id=$(get_local_id)

  resp=$(curl -s -X PUT \
    -d "{\"used\":false,\"createdAt\":${now_ms},\"expiresAt\":${expires_ms},\"generatedBy\":\"${local_id}\",\"generatedByEmail\":\"$(get_session_email)\"}" \
    "${DB_URL}/accessCodes/${code}.json")

  if echo "$resp" | grep -q "error"; then
    echo -e "${R}Gagal generate code. Response: ${resp}${NC}"
  else
    echo ""
    echo -e "${G}=== KODE AKSES BERHASIL DIBUAT ===${NC}"
    echo -e "${Y}${code}${NC}"
    echo -e "Berlaku ${hours} jam."
    echo -e "Dibuat oleh: $(get_session_email)"
  fi
  pause
}

# ============================================================
# MAIN LOOP
# ============================================================
check_deps

while true; do
  clear
  echo -e "${C}"
  echo "============================================"
  echo "        RHF ZERO - OPERATOR PANEL"
  echo "============================================"
  echo -e "${NC}"
  if is_logged_in; then
    echo -e "Login sebagai: ${G}$(get_session_name) ($(get_session_email))${NC}"
  else
    echo -e "Status: ${R}Belum login${NC}"
  fi
  echo ""
  echo "1. Alamat Web"
  echo "2. Akun"
  echo "3. Generate Code"
  echo "0. Keluar"
  echo ""
  read -p "Pilih menu: " main_opt

  case $main_opt in
    1) menu_web_address ;;
    2) menu_akun ;;
    3) menu_generate_code ;;
    0) echo "Sampai jumpa."; exit 0 ;;
    *) echo -e "${R}Pilihan tidak valid.${NC}"; sleep 1 ;;
  esac
done

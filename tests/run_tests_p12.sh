#!/usr/bin/env bash
# tests/run_tests_p12.sh - Pengujian P12: kirim arsip lewat SFTP memakai kunci SSH
# Hasil ditulis ke evidence/p12/hasil_tes_p12.txt, log tiap skenario ke evidence/p12/log_<ID>.log
# Variabel lingkungan (opsional): T_HOST, T_USER, T_PORT, T_DIR, T_KEY

set -u
cd "$(dirname "$0")/.." || exit 1

SCRIPT="./backup.sh"
EVID="evidence/p12"
RESULT="$EVID/hasil_tes_p12.txt"
T_HOST="${T_HOST:-localhost}"
T_USER="${T_USER:-backupuser}"
T_PORT="${T_PORT:-22}"
T_DIR="${T_DIR:-/incoming}"
T_KEY="${T_KEY:-$HOME/.ssh/backup_key}"
WORK="$(mktemp -d -p /tmp)"
PASS=0
FAIL=0
REMOTE_FILES=()

if [[ ! -f "$T_KEY" ]]; then
    echo "File kunci tidak ditemukan: $T_KEY (atur T_KEY)" >&2
    exit 2
fi

# shellcheck disable=SC2317,SC2329  # dipanggil tidak langsung lewat trap EXIT
cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$EVID" logs
: > "$RESULT"

say() { echo "$*" | tee -a "$RESULT"; }

# mark <deskripsi> <status: 0 = lulus, selain 0 = gagal>
mark() {
    if [[ "$2" -eq 0 ]]; then
        say "    [PASS] $1"
        PASS=$((PASS + 1))
    else
        say "    [FAIL] $1"
        FAIL=$((FAIL + 1))
    fi
}

# Menjalankan sftp ke server uji dengan kunci (perintah dari stdin).
t_sftp() {
    sftp -P "$T_PORT" -i "$T_KEY" -o IdentitiesOnly=yes -o BatchMode=yes \
        -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
        -b - "$T_USER@$T_HOST"
}

# make_conf <id> [KUNCI=nilai ...] -> mencetak path file konfigurasi
make_conf() {
    local id="$1" f line
    shift
    f="$WORK/$id.conf"
    mkdir -p "$WORK/hasil_$id"
    {
        echo "SRC_DIR=$WORK/data"
        echo "DEST_DIR=$WORK/hasil_$id"
        echo "REMOTE_HOST=$T_HOST"
        echo "REMOTE_USER=$T_USER"
        echo "REMOTE_DIR=$T_DIR"
        echo "REMOTE_PORT=$T_PORT"
        echo "SSH_KEY=$T_KEY"
        for line in "$@"; do
            echo "$line"
        done
    } > "$f"
    chmod 600 "$f"
    echo "$f"
}

# run_case <id> <deskripsi> <exit diharapkan> <argumen backup.sh...>
run_case() {
    local id="$1" desc="$2" expected="$3" actual
    shift 3
    : > logs/backup.log
    timeout 60 "$SCRIPT" "$@" > /dev/null 2>&1
    actual=$?
    cp logs/backup.log "$EVID/log_${id}.log"
    say ""
    say "[$id] $desc"
    say "    perintah       : $SCRIPT $*"
    say "    exit diharapkan: $expected"
    say "    exit aktual    : $actual"
    [[ "$actual" -eq "$expected" ]]
    mark "exit code sesuai" $?
}

# run_direct <id> <deskripsi> <pola keluaran yang diharapkan> <perintah...>
# Perintah harus gagal (exit bukan 0) dan keluarannya memuat pola.
run_direct() {
    local id="$1" desc="$2" pattern="$3" out code
    shift 3
    out="$("$@" 2>&1 < /dev/null)"
    code=$?
    out="$(printf '%s' "$out" | tr -d '\r')"
    printf '%s\n' "$out" > "$EVID/log_${id}.log"
    say ""
    say "[$id] $desc"
    say "    exit aktual    : $code"
    say "    keluaran       : $(printf '%s' "$out" | tail -n 2 | tr '\n' ' ')"
    [[ "$code" -ne 0 ]]
    mark "perintah ditolak (exit bukan 0)" $?
    printf '%s' "$out" | grep -q -i -e "$pattern"
    mark "keluaran memuat pesan penolakan yang diharapkan" $?
}

say "HASIL PENGUJIAN P12 (kirim arsip lewat SFTP dengan kunci SSH)"
say "Tanggal : $(date '+%F %T')"
say "Sistem  : $(uname -sr), bash $BASH_VERSION"
say "Klien   : $(ssh -V 2>&1)"
say "Commit  : $(git rev-parse --short HEAD 2>/dev/null || echo tidak-diketahui)"
say "Server  : $T_USER@$T_HOST port $T_PORT, folder $T_DIR (file kunci: hanya path, isinya tidak ditampilkan)"

# ---------- Data uji ----------
mkdir -p "$WORK/data"
echo "isi uji P12" > "$WORK/data/a.txt"
ssh-keygen -q -t ed25519 -f "$WORK/kunci_salah" -N ""
cp "$WORK/kunci_salah" "$WORK/kunci_longgar"
chmod 644 "$WORK/kunci_longgar"

# ---------- Skenario positif ----------
say ""
say "===== SKENARIO POSITIF (akses diizinkan) ====="

CONF_P01="$(make_conf P01)"
say ""
say "Isi konfigurasi P01 (hanya alamat dan path, tanpa credential):"
sed 's/^/        /' "$CONF_P01" | tee -a "$RESULT"
run_case P01 "POSITIF: backup dan kirim ke server dengan kunci yang benar" 0 -c "$CONF_P01" -r
arsip="$(find "$WORK/hasil_P01" -name '*.tar.gz' -print -quit)"
nama="$(basename "$arsip")"
if [[ -n "$arsip" ]]; then mark "arsip lokal terbentuk" 0; else mark "arsip lokal terbentuk" 1; fi
grep -q "Verifikasi jarak jauh OK" "$EVID/log_P01.log"
mark "log memuat verifikasi jarak jauh (SHA-256) OK" $?
listing="$(echo "ls -l $T_DIR" | t_sftp 2>&1 | tr -d '\r')"
say "    isi folder server setelah P01:"
echo "$listing" | sed 's/^/        /' | tee -a "$RESULT"
echo "$listing" | grep -q -E "^-rw-------[[:space:]].*${nama}"
mark "arsip ada di server dengan izin 600" $?
REMOTE_FILES+=("${T_DIR%/}/$nama")

CONF_P02="$(make_conf P02)"
run_case P02 "POSITIF: tanpa opsi -r hanya backup lokal (perilaku P11)" 0 -c "$CONF_P02"
! grep -q "Mengirim arsip" "$EVID/log_P02.log"
mark "log tidak memuat pengiriman jarak jauh" $?

# ---------- Skenario negatif lewat backup.sh ----------
say ""
say "===== SKENARIO NEGATIF (akses ditolak atau konfigurasi tidak valid) ====="

run_case N01 "NEGATIF: kunci SSH yang salah (tidak terdaftar di server)" 8 \
    -c "$(make_conf N01 "SSH_KEY=$WORK/kunci_salah")" -r
run_case N02 "NEGATIF: user tidak ada di server" 8 \
    -c "$(make_conf N02 "REMOTE_USER=tamu_tidak_ada")" -r
run_case N03 "NEGATIF: kunci benar dipakai untuk user lain" 8 \
    -c "$(make_conf N03 "REMOTE_USER=$(id -un)")" -r
run_case N04 "NEGATIF: izin file kunci 644 (terlalu terbuka)" 7 \
    -c "$(make_conf N04 "SSH_KEY=$WORK/kunci_longgar")" -r
run_case N05 "NEGATIF: file kunci tidak ada" 7 \
    -c "$(make_conf N05 "SSH_KEY=$WORK/tidak_ada_kunci")" -r
run_case N06 "NEGATIF: host tidak terjangkau" 8 \
    -c "$(make_conf N06 "REMOTE_HOST=192.0.2.1")" -r
run_case N07 "NEGATIF: port salah (tertutup)" 8 \
    -c "$(make_conf N07 "REMOTE_PORT=2299")" -r
run_case N08 "NEGATIF: folder tujuan di server tidak ada" 8 \
    -c "$(make_conf N08 "REMOTE_DIR=/tidak_ada")" -r
run_case N09 "NEGATIF: menulis di akar server (di luar folder incoming)" 8 \
    -c "$(make_conf N09 "REMOTE_DIR=/")" -r
run_case N10 "NEGATIF: REMOTE_DIR memuat '..'" 7 \
    -c "$(make_conf N10 "REMOTE_DIR=/incoming/../x")" -r
run_case N11 "NEGATIF: REMOTE_DIR bukan path absolut" 7 \
    -c "$(make_conf N11 "REMOTE_DIR=incoming")" -r
run_case N12 "NEGATIF: REMOTE_DIR memuat karakter berbahaya" 7 \
    -c "$(make_conf N12 "REMOTE_DIR=/incoming;rm")" -r

mkdir -p "$WORK/hasil_N13"
printf 'SRC_DIR=%s\nDEST_DIR=%s\n' "$WORK/data" "$WORK/hasil_N13" > "$WORK/N13.conf"
chmod 600 "$WORK/N13.conf"
run_case N13 "NEGATIF: opsi -r tetapi konfigurasi jarak jauh tidak lengkap" 7 \
    -c "$WORK/N13.conf" -r

# ---------- Pemeriksaan langsung akses ke server ----------
say ""
say "===== PEMERIKSAAN LANGSUNG (kontrol akses di sisi server) ====="

run_direct D01 "login dengan password ditolak (hanya kunci yang diterima)" "permission denied" \
    ssh -p "$T_PORT" -o PubkeyAuthentication=no -o PreferredAuthentications=password \
        -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$T_USER@$T_HOST" true

run_direct D02 "kunci benar tetapi menjalankan perintah shell ditolak (hanya sftp)" "sftp connections only" \
    ssh -T -p "$T_PORT" -i "$T_KEY" -o IdentitiesOnly=yes -o BatchMode=yes \
        -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$T_USER@$T_HOST" whoami

run_direct D03 "membaca file di luar folder backup ditolak (dikurung di folder rumahnya)" "not found" \
    bash -c "echo 'get /etc/passwd $WORK/passwd_uji' | sftp -P '$T_PORT' -i '$T_KEY' -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -b - '$T_USER@$T_HOST'"

say ""
say "[D04] user biasa tidak bisa membuka folder milik $T_USER"
if [[ "$EUID" -eq 0 ]]; then
    say "    DILEWATI: dijalankan sebagai root (root bisa membuka semua folder)"
elif [[ ! -d "/home/$T_USER" ]]; then
    say "    DILEWATI: /home/$T_USER tidak ada di mesin ini (server di mesin lain)"
else
    out="$(ls "/home/$T_USER" 2>&1)"
    code=$?
    say "    exit aktual    : $code"
    say "    keluaran       : $out"
    [[ "$code" -ne 0 ]]
    mark "folder backup tidak bisa dibuka oleh user biasa" $?
fi

# ---------- Keamanan bukti ----------
say ""
say "[KEAMANAN] pemeriksaan isi bukti"
if grep -r -q -i "PRIVATE KEY" "$EVID"; then
    mark "tidak ada penanda private key di folder bukti" 1
else
    mark "tidak ada penanda private key di folder bukti" 0
fi
if sed '1d;$d' "$T_KEY" | grep -r -q -F -f - "$EVID"; then
    mark "isi file kunci tidak muncul di folder bukti" 1
else
    mark "isi file kunci tidak muncul di folder bukti" 0
fi

# ---------- Bersihkan berkas uji di server ----------
say ""
say "[CLEANUP] menghapus arsip uji yang dikirim tes ini dari server"
for f in "${REMOTE_FILES[@]}"; do
    printf 'rm %s\n' "$f" | t_sftp > /dev/null 2>&1
    say "    dihapus: $f"
done

say ""
say "RINGKASAN: $PASS cek lulus, $FAIL cek gagal"

if [[ "$FAIL" -eq 0 ]]; then
    exit 0
else
    exit 1
fi

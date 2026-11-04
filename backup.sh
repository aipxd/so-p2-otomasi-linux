#!/usr/bin/env bash
# backup.sh - Otomasi backup folder menjadi arsip tar.gz berstempel waktu.
# Opsional: arsip dikirim ke server jarak jauh lewat SFTP memakai kunci SSH.
# Proyek 2 (Otomasi dan Container Linux) - Checkpoint P11 dan P12

set -u
set -o pipefail

# ---------- Exit code ----------
readonly EXIT_OK=0
readonly EXIT_USAGE=1
readonly EXIT_SRC_INVALID=2
readonly EXIT_DEST_INVALID=3
readonly EXIT_ARCHIVE_FAIL=4
readonly EXIT_VERIFY_FAIL=5
readonly EXIT_CONFIG_INVALID=6
readonly EXIT_REMOTE_CONFIG=7
readonly EXIT_REMOTE_FAIL=8
readonly EXIT_REMOTE_VERIFY=9

# ---------- Variabel default ----------
SRC_DIR=""
DEST_DIR=""
SRC_ABS=""
DEST_ABS=""
ARCHIVE_FILE=""
LOG_FILE="./logs/backup.log"
LOG_READY=0
CONFIG_FILE=""
REMOTE_ENABLED=0
REMOTE_HOST=""
REMOTE_USER=""
REMOTE_DIR=""
REMOTE_PORT="22"
SSH_KEY=""

# ---------- Fungsi ----------
log() {
    local level="$1"; shift
    local line
    line="[$(date '+%F %T')] [$level] $*"
    echo "$line"
    if [[ "$LOG_READY" -eq 1 ]]; then
        echo "$line" >> "$LOG_FILE"
    fi
}

init_log() {
    local log_dir
    log_dir="$(dirname "$LOG_FILE")"
    if mkdir -p "$log_dir" 2>/dev/null && touch "$LOG_FILE" 2>/dev/null; then
        LOG_READY=1
    else
        echo "[PERINGATAN] File log tidak bisa ditulis: $LOG_FILE (log hanya ke layar)" >&2
    fi
}

usage() {
    cat << USAGE
Penggunaan: $0 [-s <folder_sumber>] [-d <folder_tujuan>] [-c <file_config>] [-r] [-h]

  -s  folder yang akan di-backup
  -d  folder tempat arsip disimpan
  -c  file konfigurasi (SRC_DIR, DEST_DIR, dan pengaturan jarak jauh)
  -r  setelah backup lokal, kirim arsip ke server jarak jauh lewat SFTP
      (butuh REMOTE_HOST, REMOTE_USER, REMOTE_DIR, SSH_KEY di file konfigurasi)
  -h  tampilkan bantuan ini

Sumber dan tujuan wajib ada, dari parameter atau dari file konfigurasi.
Parameter command line mengalahkan nilai di file konfigurasi.

Contoh:
  $0 -s ./data -d ./backups
  $0 -c config/backup.conf
  $0 -c config/backup.conf -r
USAGE
}

parse_args() {
    local opt
    while getopts ":s:d:c:rh" opt; do
        case "$opt" in
            s) SRC_DIR="$OPTARG" ;;
            d) DEST_DIR="$OPTARG" ;;
            c) CONFIG_FILE="$OPTARG" ;;
            r) REMOTE_ENABLED=1 ;;
            h) usage; exit "$EXIT_OK" ;;
            :)  log ERROR "Opsi -$OPTARG membutuhkan nilai"; usage; exit "$EXIT_USAGE" ;;
            \?) log ERROR "Opsi tidak dikenal: -$OPTARG"; usage; exit "$EXIT_USAGE" ;;
        esac
    done
}

load_config() {
    local line key value lineno=0

    if [[ -z "$CONFIG_FILE" ]]; then
        log INFO "Tidak memakai file konfigurasi"
        return 0
    fi
    if [[ ! -f "$CONFIG_FILE" || ! -r "$CONFIG_FILE" ]]; then
        log ERROR "File konfigurasi tidak ditemukan atau tidak bisa dibaca: $CONFIG_FILE"
        exit "$EXIT_CONFIG_INVALID"
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))
        # lewati baris kosong dan komentar
        [[ -z "${line//[[:space:]]/}" || "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ ! "$line" =~ ^[[:space:]]*([A-Z_]+)=(.*)$ ]]; then
            log ERROR "Config baris $lineno tidak valid (format harus KUNCI=nilai)"
            exit "$EXIT_CONFIG_INVALID"
        fi
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        value="${value%\"}"
        value="${value#\"}"

        case "$key" in
            SRC_DIR)     [[ -z "$SRC_DIR" ]] && SRC_DIR="$value" ;;
            DEST_DIR)    [[ -z "$DEST_DIR" ]] && DEST_DIR="$value" ;;
            REMOTE_HOST) REMOTE_HOST="$value" ;;
            REMOTE_USER) REMOTE_USER="$value" ;;
            REMOTE_DIR)  REMOTE_DIR="$value" ;;
            REMOTE_PORT) REMOTE_PORT="$value" ;;
            SSH_KEY)     SSH_KEY="$value" ;;
            *)
                log ERROR "Config baris $lineno: kunci tidak dikenal: $key"
                exit "$EXIT_CONFIG_INVALID"
                ;;
        esac
    done < "$CONFIG_FILE"

    log INFO "Konfigurasi dimuat dari $CONFIG_FILE"
}

check_required() {
    if [[ -z "$SRC_DIR" || -z "$DEST_DIR" ]]; then
        log ERROR "Folder sumber dan tujuan wajib diisi (lewat -s dan -d, atau file konfigurasi)"
        usage
        exit "$EXIT_USAGE"
    fi
}

validate_input() {
    if [[ ! -e "$SRC_DIR" ]]; then
        log ERROR "Folder sumber tidak ditemukan: $SRC_DIR"
        exit "$EXIT_SRC_INVALID"
    fi
    if [[ ! -d "$SRC_DIR" ]]; then
        log ERROR "Sumber bukan sebuah folder: $SRC_DIR"
        exit "$EXIT_SRC_INVALID"
    fi
    if [[ ! -r "$SRC_DIR" ]]; then
        log ERROR "Folder sumber tidak bisa dibaca: $SRC_DIR"
        exit "$EXIT_SRC_INVALID"
    fi
    if [[ ! -d "$DEST_DIR" ]]; then
        log ERROR "Folder tujuan tidak ditemukan: $DEST_DIR"
        exit "$EXIT_DEST_INVALID"
    fi
    if [[ ! -w "$DEST_DIR" ]]; then
        log ERROR "Folder tujuan tidak bisa ditulis: $DEST_DIR"
        exit "$EXIT_DEST_INVALID"
    fi

    SRC_ABS="$(cd "$SRC_DIR" && pwd -P)"
    DEST_ABS="$(cd "$DEST_DIR" && pwd -P)"

    if [[ "$SRC_ABS" == "/" ]]; then
        log ERROR "Folder sumber '/' ditolak demi keamanan"
        exit "$EXIT_SRC_INVALID"
    fi
    case "$DEST_ABS/" in
        "$SRC_ABS"/*)
            log ERROR "Folder tujuan tidak boleh berada di dalam folder sumber"
            exit "$EXIT_DEST_INVALID"
            ;;
    esac

    log INFO "Validasi input OK (sumber=$SRC_ABS, tujuan=$DEST_ABS)"
}

# Memeriksa pengaturan jarak jauh sebelum arsip dibuat (hanya jika opsi -r dipakai).
validate_remote_config() {
    local perm

    if [[ "$REMOTE_ENABLED" -ne 1 ]]; then
        return 0
    fi

    if [[ -z "$REMOTE_HOST" || -z "$REMOTE_USER" || -z "$REMOTE_DIR" || -z "$SSH_KEY" ]]; then
        log ERROR "Opsi -r membutuhkan REMOTE_HOST, REMOTE_USER, REMOTE_DIR, dan SSH_KEY di file konfigurasi"
        exit "$EXIT_REMOTE_CONFIG"
    fi
    if [[ ! "$REMOTE_HOST" =~ ^[A-Za-z0-9._-]+$ ]]; then
        log ERROR "REMOTE_HOST memuat karakter yang tidak diizinkan"
        exit "$EXIT_REMOTE_CONFIG"
    fi
    if [[ ! "$REMOTE_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        log ERROR "REMOTE_USER memuat karakter yang tidak diizinkan"
        exit "$EXIT_REMOTE_CONFIG"
    fi
    if [[ ! "$REMOTE_PORT" =~ ^[0-9]{1,5}$ ]] || (( 10#$REMOTE_PORT < 1 || 10#$REMOTE_PORT > 65535 )); then
        log ERROR "REMOTE_PORT harus angka 1 sampai 65535"
        exit "$EXIT_REMOTE_CONFIG"
    fi
    if [[ ! "$REMOTE_DIR" =~ ^/[A-Za-z0-9._/-]*$ || "$REMOTE_DIR" == *..* ]]; then
        log ERROR "REMOTE_DIR harus path absolut tanpa spasi atau '..' (contoh: /incoming)"
        exit "$EXIT_REMOTE_CONFIG"
    fi
    if [[ ! "$DEST_ABS/$(basename "$SRC_ABS")" =~ ^[A-Za-z0-9._/-]+$ ]]; then
        log ERROR "Nama folder sumber atau tujuan memuat spasi atau karakter khusus, tidak bisa dikirim jarak jauh"
        exit "$EXIT_REMOTE_CONFIG"
    fi
    if ! command -v sftp > /dev/null 2>&1 || ! command -v sha256sum > /dev/null 2>&1; then
        log ERROR "Perintah sftp atau sha256sum tidak ditemukan"
        exit "$EXIT_REMOTE_CONFIG"
    fi
    if [[ ! -f "$SSH_KEY" || ! -r "$SSH_KEY" ]]; then
        log ERROR "File kunci SSH tidak ditemukan atau tidak bisa dibaca: $SSH_KEY (gunakan path absolut)"
        exit "$EXIT_REMOTE_CONFIG"
    fi
    perm="$(stat -c %a "$SSH_KEY")"
    if [[ "${perm: -2}" != "00" ]]; then
        log ERROR "Izin file kunci terlalu terbuka ($perm). Perbaiki dengan: chmod 600 $SSH_KEY"
        exit "$EXIT_REMOTE_CONFIG"
    fi

    log INFO "Pengaturan jarak jauh OK (${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}, port ${REMOTE_PORT})"
}

create_backup() {
    local ts base parent tmp_file tar_err
    ts="$(date '+%Y%m%d_%H%M%S')"
    base="$(basename "$SRC_ABS")"
    parent="$(dirname "$SRC_ABS")"
    ARCHIVE_FILE="$DEST_ABS/${base}_${ts}.tar.gz"
    tmp_file="${ARCHIVE_FILE}.part"

    if [[ -e "$ARCHIVE_FILE" ]]; then
        log ERROR "Arsip sudah ada dan tidak ditimpa: $ARCHIVE_FILE"
        exit "$EXIT_ARCHIVE_FAIL"
    fi

    log INFO "Membuat arsip: $ARCHIVE_FILE"
    if ! tar_err="$(tar -czf "$tmp_file" -C "$parent" "$base" 2>&1)"; then
        log ERROR "Gagal membuat arsip dari $SRC_ABS"
        log ERROR "Pesan tar: $tar_err"
        rm -f "$tmp_file"
        exit "$EXIT_ARCHIVE_FAIL"
    fi

    if ! mv "$tmp_file" "$ARCHIVE_FILE"; then
        log ERROR "Gagal menamai ulang arsip sementara"
        rm -f "$tmp_file"
        exit "$EXIT_ARCHIVE_FAIL"
    fi
    log INFO "Arsip berhasil dibuat"
}

verify_backup() {
    local size
    if [[ ! -s "$ARCHIVE_FILE" ]]; then
        log ERROR "Arsip kosong atau tidak ada: $ARCHIVE_FILE"
        exit "$EXIT_VERIFY_FAIL"
    fi
    if ! tar -tzf "$ARCHIVE_FILE" > /dev/null 2>&1; then
        log ERROR "Arsip tidak bisa dibaca (rusak), arsip dihapus: $ARCHIVE_FILE"
        rm -f "$ARCHIVE_FILE"
        exit "$EXIT_VERIFY_FAIL"
    fi
    size="$(stat -c %s "$ARCHIVE_FILE")"
    log INFO "Verifikasi OK: $ARCHIVE_FILE (${size} byte)"
}

# Menjalankan sftp dengan kunci, tanpa password, perintahnya dibaca dari stdin.
run_sftp() {
    sftp -i "$SSH_KEY" -P "$REMOTE_PORT" \
        -o IdentitiesOnly=yes -o BatchMode=yes \
        -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
        -b - "${REMOTE_USER}@${REMOTE_HOST}"
}

# Mengubah pesan sftp yang panjang menjadi satu baris agar log tetap rapi.
clean_msg() {
    printf '%s' "$1" | tr '\r\n' '  '
}

# Menghapus berkas di server (upaya terbaik), dipakai saat pengiriman gagal.
remote_remove() {
    printf 'rm %s\n' "$1" | run_sftp > /dev/null 2>&1 || true
}

send_remote() {
    local dst out

    if [[ "$REMOTE_ENABLED" -ne 1 ]]; then
        return 0
    fi

    dst="${REMOTE_DIR%/}/$(basename "$ARCHIVE_FILE")"
    log INFO "Mengirim arsip ke ${REMOTE_USER}@${REMOTE_HOST}:${dst} (port ${REMOTE_PORT})"

    if ! out="$(printf 'put %s %s.part\nrename %s.part %s\n' \
            "$ARCHIVE_FILE" "$dst" "$dst" "$dst" | run_sftp 2>&1)"; then
        log ERROR "Pengiriman ke server gagal"
        log ERROR "Pesan sftp: $(clean_msg "$out")"
        remote_remove "${dst}.part"
        exit "$EXIT_REMOTE_FAIL"
    fi
    log INFO "Arsip terkirim: $dst"
}

# Mengunduh kembali arsip dari server lalu membandingkan SHA-256 dengan arsip lokal.
verify_remote() {
    local dst tmp_dir out local_sum remote_sum

    if [[ "$REMOTE_ENABLED" -ne 1 ]]; then
        return 0
    fi

    dst="${REMOTE_DIR%/}/$(basename "$ARCHIVE_FILE")"
    if ! tmp_dir="$(mktemp -d -p /tmp)"; then
        log ERROR "Gagal membuat folder sementara untuk verifikasi jarak jauh"
        exit "$EXIT_REMOTE_VERIFY"
    fi

    if ! out="$(printf 'get %s %s/arsip_uji\n' "$dst" "$tmp_dir" | run_sftp 2>&1)"; then
        rm -rf "$tmp_dir"
        log ERROR "Gagal mengunduh kembali arsip dari server untuk verifikasi"
        log ERROR "Pesan sftp: $(clean_msg "$out")"
        exit "$EXIT_REMOTE_VERIFY"
    fi

    local_sum="$(sha256sum "$ARCHIVE_FILE" | cut -d' ' -f1)"
    remote_sum="$(sha256sum "$tmp_dir/arsip_uji" | cut -d' ' -f1)"
    rm -rf "$tmp_dir"

    if [[ "$local_sum" != "$remote_sum" ]]; then
        log ERROR "Checksum arsip di server berbeda dari arsip lokal"
        log ERROR "Lokal: $local_sum"
        log ERROR "Server: $remote_sum"
        remote_remove "$dst"
        exit "$EXIT_REMOTE_VERIFY"
    fi
    log INFO "Verifikasi jarak jauh OK (SHA-256: $local_sum)"
}

main() {
    init_log
    log INFO "Script dimulai"
    parse_args "$@"
    load_config
    check_required
    validate_input
    validate_remote_config
    create_backup
    verify_backup
    send_remote
    verify_remote
    log INFO "Proses selesai"
    exit "$EXIT_OK"
}

main "$@"

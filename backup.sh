#!/usr/bin/env bash
# backup.sh - Otomasi backup folder menjadi arsip tar.gz berstempel waktu
# Proyek 2 (Otomasi dan Container Linux) - Checkpoint P11

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

# ---------- Variabel default ----------
SRC_DIR=""
DEST_DIR=""
SRC_ABS=""
DEST_ABS=""
ARCHIVE_FILE=""
LOG_FILE="./logs/backup.log"
LOG_READY=0
CONFIG_FILE=""

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
Penggunaan: $0 [-s <folder_sumber>] [-d <folder_tujuan>] [-c <file_config>] [-h]

  -s  folder yang akan di-backup
  -d  folder tempat arsip disimpan
  -c  file konfigurasi (isi: SRC_DIR=... dan DEST_DIR=...)
  -h  tampilkan bantuan ini

Sumber dan tujuan wajib ada, dari parameter atau dari file konfigurasi.
Parameter command line mengalahkan nilai di file konfigurasi.

Contoh:
  $0 -s ./data -d ./backups
  $0 -c config/backup.conf
USAGE
}

parse_args() {
    local opt
    while getopts ":s:d:c:h" opt; do
        case "$opt" in
            s) SRC_DIR="$OPTARG" ;;
            d) DEST_DIR="$OPTARG" ;;
            c) CONFIG_FILE="$OPTARG" ;;
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
            SRC_DIR)  [[ -z "$SRC_DIR" ]] && SRC_DIR="$value" ;;
            DEST_DIR) [[ -z "$DEST_DIR" ]] && DEST_DIR="$value" ;;
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

main() {
    init_log
    log INFO "Script dimulai"
    parse_args "$@"
    load_config
    check_required
    validate_input
    create_backup
    verify_backup
    log INFO "Proses selesai"
    exit "$EXIT_OK"
}

main "$@"

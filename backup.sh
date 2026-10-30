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

# ---------- Variabel default ----------
SRC_DIR=""
DEST_DIR=""
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
Penggunaan: $0 -s <folder_sumber> -d <folder_tujuan> [-c <file_config>] [-h]

  -s  folder yang akan di-backup (wajib)
  -d  folder tempat arsip disimpan (wajib)
  -c  file konfigurasi (opsional)
  -h  tampilkan bantuan ini

Contoh:
  $0 -s ./data -d ./backups
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

    if [[ -z "$SRC_DIR" || -z "$DEST_DIR" ]]; then
        log ERROR "Parameter -s dan -d wajib diisi"
        usage
        exit "$EXIT_USAGE"
    fi
}

load_config() {
    log TODO "load_config belum dibuat"
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
    log INFO "Validasi input OK (sumber=$SRC_DIR, tujuan=$DEST_DIR)"
}

create_backup() {
    log TODO "create_backup belum dibuat"
}

verify_backup() {
    log TODO "verify_backup belum dibuat"
}

main() {
    init_log
    log INFO "Script dimulai"
    parse_args "$@"
    load_config
    validate_input
    create_backup
    verify_backup
    log INFO "Proses selesai"
    exit "$EXIT_OK"
}

main "$@"

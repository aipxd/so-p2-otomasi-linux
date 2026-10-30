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
CONFIG_FILE=""

# ---------- Fungsi ----------
log() {
    local level="$1"; shift
    echo "[$(date '+%F %T')] [$level] $*"
}

usage() {
    log TODO "usage belum dibuat"
}

parse_args() {
    log TODO "parse_args belum dibuat"
}

load_config() {
    log TODO "load_config belum dibuat"
}

validate_input() {
    log TODO "validate_input belum dibuat"
}

create_backup() {
    log TODO "create_backup belum dibuat"
}

verify_backup() {
    log TODO "verify_backup belum dibuat"
}

main() {
    parse_args "$@"
    load_config
    validate_input
    create_backup
    verify_backup
    log INFO "Proses selesai"
    exit "$EXIT_OK"
}

main "$@"

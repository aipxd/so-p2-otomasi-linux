#!/usr/bin/env bash
# tests/run_tests.sh - Pengujian backup.sh
# Hasil ditulis ke evidence/hasil_tes.txt, log tiap skenario ke evidence/log_<ID>.log

set -u
cd "$(dirname "$0")/.." || exit 1

SCRIPT="./backup.sh"
EVID="evidence"
RESULT="$EVID/hasil_tes.txt"
WORK="$(mktemp -d)"
PASS=0
FAIL=0

cleanup() {
    chmod -R u+rwx "$WORK" 2>/dev/null
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

# run_case <id> <deskripsi> <exit code diharapkan> <argumen backup.sh...>
run_case() {
    local id="$1" desc="$2" expected="$3"
    shift 3
    local actual
    : > logs/backup.log
    "$SCRIPT" "$@" > /dev/null 2>&1
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

say "HASIL PENGUJIAN backup.sh"
say "Tanggal : $(date '+%F %T')"
say "Sistem  : $(uname -sr), bash $BASH_VERSION"

# ---------- Data uji ----------
mkdir -p "$WORK/sumber" "$WORK/hasil_ok"
echo "isi uji" > "$WORK/sumber/a.txt"

# ---------- T01: skenario sukses ----------
run_case T01 "SUKSES: backup folder yang valid" 0 -s "$WORK/sumber" -d "$WORK/hasil_ok"
arsip="$(ls "$WORK/hasil_ok"/*.tar.gz 2>/dev/null | head -n 1)"
[[ -n "$arsip" ]]
mark "arsip .tar.gz terbentuk" $?
[[ -n "$arsip" ]] && tar -tzf "$arsip" | grep -q "sumber/a.txt"
mark "arsip berisi sumber/a.txt" $?

# ---------- T02 - T08: skenario gagal ----------
run_case T02 "GAGAL: tanpa parameter" 1

run_case T03 "GAGAL: folder sumber tidak ada" 2 -s "$WORK/tidak_ada" -d "$WORK/hasil_ok"

run_case T04 "GAGAL: folder tujuan tidak ada" 3 -s "$WORK/sumber" -d "$WORK/tidak_ada"

mkdir -p "$WORK/sumber2/dalam"
run_case T05 "GAGAL: folder tujuan di dalam folder sumber" 3 -s "$WORK/sumber2" -d "$WORK/sumber2/dalam"

run_case T06 "GAGAL: file konfigurasi tidak ada" 6 -c "$WORK/tidak_ada.conf"

echo "FOO=bar" > "$WORK/salah.conf"
run_case T07 "GAGAL: isi konfigurasi tidak valid" 6 -c "$WORK/salah.conf"

if [[ "$EUID" -eq 0 ]]; then
    say ""
    say "[T08] DILEWATI: dijalankan sebagai root (chmod 000 tidak berlaku untuk root)"
else
    mkdir -p "$WORK/sumber_rusak" "$WORK/hasil_gagal"
    echo "rahasia" > "$WORK/sumber_rusak/x.txt"
    chmod 000 "$WORK/sumber_rusak/x.txt"
    run_case T08 "GAGAL: ada file yang tidak bisa dibaca" 4 -s "$WORK/sumber_rusak" -d "$WORK/hasil_gagal"
    [[ -z "$(ls -A "$WORK/hasil_gagal")" ]]
    mark "tidak ada arsip atau file .part yang tersisa" $?
fi

say ""
say "RINGKASAN: $PASS cek lulus, $FAIL cek gagal"

if [[ "$FAIL" -eq 0 ]]; then
    exit 0
else
    exit 1
fi

# Changelog

## P12 (tag P2-CHECKPOINT-P12-v01) - 2026-11-05

Dasar: tag P2-CHECKPOINT-P11-v01 (commit 324a963).

### Ditambahkan
- Opsi `-r` di `backup.sh`: kirim arsip ke server lewat SFTP memakai kunci SSH, lalu unduh
  kembali dan bandingkan SHA-256.
- Kunci konfigurasi `REMOTE_HOST`, `REMOTE_USER`, `REMOTE_DIR`, `REMOTE_PORT`, `SSH_KEY`.
- Exit code 7 (pengaturan jarak jauh tidak valid), 8 (pengiriman gagal), 9 (verifikasi jarak jauh gagal).
- `tests/run_tests_p12.sh`: 2 skenario positif, 13 skenario negatif, 4 pemeriksaan akses langsung.
- `docs/ANALISIS_P12.md` dan `docs/CLEANUP_ROLLBACK_P12.md`.
- Bukti P12 di `evidence/p12/`.

### Diubah
- `config/backup.conf.example` memuat pengaturan jarak jauh (tanpa credential).
- README: bagian 14 (P12), tabel struktur repository dan exit status diperbarui.

### Keamanan
- File kunci harus berizin 600, kalau tidak script berhenti.
- Nilai konfigurasi jarak jauh divalidasi dengan pola ketat (tanpa spasi, `..`, atau karakter khusus).
- Pengiriman ke berkas `.part` lalu diganti nama, sehingga tidak ada berkas setengah jadi di server.
- Di server: user `backupuser` tanpa shell, password dimatikan, chroot, hanya sftp.

### Tidak berubah
- Tanpa opsi `-r`, perilaku sama dengan P11 (tes P11 tetap lulus).

## P11 (tag P2-CHECKPOINT-P11-v01, commit 324a963) - 2026-10-30

- `backup.sh`: backup folder menjadi arsip `.tar.gz` berstempel waktu, validasi parameter,
  file konfigurasi, logging ke `logs/backup.log`, dan exit code 0 sampai 6.
- `tests/run_tests.sh`: 1 skenario sukses dan 7 skenario gagal, hasil di `evidence/`.
- README, catatan kontribusi, review `shellcheck`, dan verifikasi reproduksi.

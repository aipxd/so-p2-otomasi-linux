# Prosedur Cleanup dan Rollback (P12)

Hasil eksekusi nyata tersimpan di `evidence/p12/cleanup_rollback.txt`.

## 1. Cleanup (sudah dijalankan)

Membersihkan berkas uji tanpa mengubah layanan:

```bash
# hapus berkas uji di server (lewat sftp dengan kunci backup)
printf 'rm /incoming/<nama_berkas>\n' | sftp -i ~/.ssh/backup_key -o IdentitiesOnly=yes -b - backupuser@localhost

# hapus folder uji lokal, config uji, dan log lokal
rm -rf ~/uji_p12
rm -f config/backup.conf logs/backup.log
```

Hasil: folder `/incoming` kosong, `config/` hanya berisi `backup.conf.example`.
Untuk memakai lagi: `cp config/backup.conf.example config/backup.conf`, sesuaikan isinya,
lalu `chmod 600 config/backup.conf`.

Skrip `tests/run_tests_p12.sh` menghapus sendiri arsip uji yang dikirimnya dari server.

## 2. Rollback akses: mencabut kunci (sudah dijalankan)

```bash
AK=/home/backupuser/.ssh/authorized_keys
sudo mv "$AK" "$AK.dicabut"          # cabut akses
./backup.sh -c <config> -r           # hasil: exit 8 (ditolak)
sudo mv "$AK.dicabut" "$AK"          # pulihkan akses
./backup.sh -c <config> -r           # hasil: exit 0
```

Hasil aktual: exit 8 saat dicabut, exit 0 setelah dipulihkan, izin `authorized_keys`
kembali `-rw-------` milik `backupuser`. Arsip lokal tetap tersimpan walau pengiriman gagal.

Untuk mencabut akses secara permanen, hapus berkas `authorized_keys` atau baris kuncinya,
lalu buat pasangan kunci baru jika masih diperlukan.

## 3. Rollback kode ke P11 (sudah dijalankan)

Menjalankan versi P11 dari tag tanpa mengubah repo:

```bash
mkdir -p /tmp/rb/p11
git show P2-CHECKPOINT-P11-v01:backup.sh > /tmp/rb/p11/backup.sh
chmod +x /tmp/rb/p11/backup.sh
```

Hasil aktual: versi P11 berjalan normal tanpa `-r` (exit 0) dan menolak `-r`
(`Opsi tidak dikenal`, exit 1). `git status` repo utama tidak berubah.

Rollback permanen di repo (riwayat commit tidak dihapus):

```bash
# mengembalikan file ke versi P11, lalu commit
git checkout P2-CHECKPOINT-P11-v01 -- backup.sh config/backup.conf.example
git commit -m "revert: kembali ke versi P11"

# atau membatalkan satu commit tertentu
git revert <commit_id>
```

## 4. Pembongkaran total layanan (prosedur, TIDAK dijalankan)

Tidak dijalankan karena layanan ini masih dipakai pada tahap P13 sampai P15. Perintah
berikut disusun dari perintah standar Ubuntu dan belum diuji pada VM ini.

```bash
sudo rm /etc/ssh/sshd_config.d/99-backupuser.conf   # hapus pembatasan sshd
sudo sshd -t && sudo systemctl reload ssh           # periksa lalu terapkan
sudo deluser --remove-home backupuser               # hapus user dan foldernya
getent group backupuser                             # jika grup masih ada: sudo delgroup backupuser
rm -f ~/.ssh/backup_key ~/.ssh/backup_key.pub       # hapus pasangan kunci backup
ssh-keygen -R localhost                             # hapus entri host key dari known_hosts
```

Verifikasi setelah pembongkaran: `getent passwd backupuser` tidak menampilkan apa pun, dan
`./backup.sh -c <config> -r` gagal. Alternatif yang lebih cepat adalah mengembalikan
snapshot VM yang dibuat sebelum P12 (jika ada).

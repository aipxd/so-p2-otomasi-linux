# Otomasi Backup Folder (Proyek 2, Checkpoint P11)

Modul otomasi administrasi Linux berupa shell script yang membuat arsip `.tar.gz`
berstempel waktu dari sebuah folder, memverifikasi arsipnya, dan mencatat semua
aktivitas ke dalam log.

## 1. Use case dan tujuan

- **Use case:** backup folder data ke folder tujuan sebagai arsip terkompresi.
- **Tujuan otomasi:** membuat backup yang konsisten (nama arsip berstempel waktu),
  aman (tidak menimpa arsip lama, tidak meninggalkan arsip setengah jadi), dan
  dapat ditelusuri lewat log, tanpa perlu mengetik perintah `tar` secara manual.
- Dirancang sebagai dasar yang dikembangkan pada tahap P12-P15.

## 2. Struktur repository

| Path | Fungsi |
|---|---|
| `backup.sh` | Script utama |
| `config/backup.conf.example` | Contoh konfigurasi (tanpa credential) |
| `tests/run_tests.sh` | Skrip pengujian: 1 skenario sukses dan 7 skenario gagal |
| `evidence/` | Hasil nyata pengujian (`hasil_tes.txt`) dan log tiap skenario |
| `logs/` | Log saat script berjalan (tidak di-commit) |

## 3. Lingkungan

Diuji pada Ubuntu 26.04.1 LTS, bash 5.3.9, GNU tar 1.35. Membutuhkan `bash`, `tar`,
`stat`, dan `date` (bawaan Linux). Tidak membutuhkan hak akses root.

## 4. Cara menjalankan

Jalankan dari folder utama repository, karena log ditulis ke `./logs/backup.log`
relatif terhadap folder tempat script dijalankan.

```bash
git clone git@github.com:aipxd/so-p2-otomasi-linux.git
cd so-p2-otomasi-linux
chmod +x backup.sh tests/run_tests.sh
```

Dengan parameter:

```bash
mkdir -p ~/data ~/backups
./backup.sh -s ~/data -d ~/backups
```

Dengan file konfigurasi:

```bash
cp config/backup.conf.example config/backup.conf
# edit SRC_DIR dan DEST_DIR di config/backup.conf (gunakan path absolut)
./backup.sh -c config/backup.conf
```

| Opsi | Fungsi |
|---|---|
| `-s` | Folder yang akan di-backup |
| `-d` | Folder tujuan arsip (harus sudah ada dan bisa ditulis) |
| `-c` | File konfigurasi berisi `SRC_DIR=` dan `DEST_DIR=` |
| `-h` | Tampilkan bantuan |

Jika parameter dan konfigurasi sama-sama diberikan, **parameter command line
mengalahkan nilai di konfigurasi**. File `config/backup.conf` yang asli tidak ikut
di-commit (lihat `.gitignore`).

## 5. Exit status

| Kode | Arti |
|---|---|
| 0 | Sukses, arsip terbentuk dan lolos verifikasi |
| 1 | Parameter kurang atau opsi salah |
| 2 | Folder sumber tidak ada, bukan folder, tidak bisa dibaca, atau `/` |
| 3 | Folder tujuan tidak ada, tidak bisa ditulis, atau berada di dalam folder sumber |
| 4 | Gagal membuat arsip, atau arsip dengan nama yang sama sudah ada |
| 5 | Verifikasi arsip gagal (kosong atau tidak bisa dibaca) |
| 6 | File konfigurasi tidak ada atau isinya tidak valid |

## 6. Cara memverifikasi hasil

```bash
echo "exit code: $?"            # jalankan segera setelah backup.sh
ls -l ~/backups                  # arsip data_<tanggal>_<jam>.tar.gz ada
tar -tzf ~/backups/<nama_arsip>.tar.gz   # lihat isi arsip tanpa mengekstrak
cat logs/backup.log              # catatan aktivitas
```

Menjalankan seluruh pengujian:

```bash
./tests/run_tests.sh
```

Skrip tes membuat folder sementara sendiri dan menghapusnya setelah selesai. Hasilnya
ditulis ke `evidence/hasil_tes.txt`, dan log tiap skenario ke `evidence/log_T0X.log`.

## 7. Pengujian dan hasil

| ID | Skenario | Exit diharapkan |
|---|---|---|
| T01 | Sukses: backup folder valid | 0 |
| T02 | Gagal: tanpa parameter | 1 |
| T03 | Gagal: folder sumber tidak ada | 2 |
| T04 | Gagal: folder tujuan tidak ada | 3 |
| T05 | Gagal: tujuan di dalam sumber | 3 |
| T06 | Gagal: file konfigurasi tidak ada | 6 |
| T07 | Gagal: isi konfigurasi tidak valid | 6 |
| T08 | Gagal: ada file yang tidak bisa dibaca | 4 |

Hasil aktual dari eksekusi terakhir tercatat di `evidence/hasil_tes.txt`: seluruh
11 pengecekan lulus. Output dinamis (stempel waktu, nama folder sementara) berbeda
pada tiap eksekusi dan tiap sistem.

**Interpretasi singkat:** skenario sukses (T01) menghasilkan arsip yang benar-benar
berisi file sumber. Setiap skenario gagal ditolak dengan exit code yang berbeda dan
sesuai penyebabnya, dengan pesan error yang tercatat di log. Pada T08, kegagalan di
tengah proses tidak meninggalkan arsip atau file `.part`, sehingga tidak ada backup
setengah jadi.

## 8. Logging

Setiap kejadian dicatat dengan format `[tanggal jam] [LEVEL] pesan` ke layar dan ke
`logs/backup.log` (mode tambah, tidak menimpa). Level yang dipakai: `INFO` dan
`ERROR`. Contoh log kondisi berhasil dan gagal ada di `evidence/log_T01.log` (sukses)
serta `evidence/log_T03.log` sampai `evidence/log_T08.log` (gagal).

## 9. Pembersihan

Hapus arsip uji, log, dan folder percobaan yang tidak diperlukan:

```bash
rm -f ~/backups/data_*.tar.gz
rm -f logs/backup.log
rm -rf ~/data ~/backups      # hanya jika folder ini memang dibuat untuk percobaan
```

Hapus dengan hati-hati: perintah `rm` tidak bisa dibatalkan. Script ini sendiri tidak
pernah menghapus atau mengubah folder sumber.

## 10. Rollback

- **Membatalkan satu backup:** hapus arsip yang dibuat, `rm <folder_tujuan>/<nama_arsip>.tar.gz`.
  Folder sumber tidak berubah, jadi tidak ada yang perlu dipulihkan.
- **Memulihkan data dari arsip:** ekstrak ke lokasi yang dipilih,
  `tar -xzf <nama_arsip>.tar.gz -C <folder_pemulihan>`. Isi folder sumber akan muncul
  di dalam folder dengan nama aslinya.
- **Kembali ke versi script sebelumnya:** `git log --oneline` untuk melihat riwayat,
  lalu `git checkout <commit_id_atau_tag> -- backup.sh`.

## 11. Keamanan

- Tidak ada password, token, private key, atau data pribadi di repository.
  File konfigurasi hanya berisi path folder.
- File konfigurasi dibaca baris per baris dan **tidak dijalankan** sebagai script;
  hanya kunci `SRC_DIR` dan `DEST_DIR` yang diterima.
- Folder sumber `/` ditolak, arsip lama tidak pernah ditimpa, dan folder tujuan tidak
  boleh berada di dalam folder sumber.
- Arsip ditulis dulu ke file `.part`, lalu diganti namanya hanya jika `tar` sukses.

## 12. Batasan dan pengembangan berikutnya

- Belum ada penjadwalan otomatis (cron/systemd timer).
- Belum ada rotasi atau penghapusan backup lama.
- Belum ada checksum atau enkripsi arsip.
- Path di konfigurasi harus absolut (tanda `~` tidak diperluas).
- Lokasi log tetap `./logs/backup.log`, sehingga script perlu dijalankan dari folder
  repository.
- Nama arsip berstempel waktu per detik, sehingga dua backup dari folder bernama sama dalam detik yang sama ditolak (exit 4) dan harus diulang setelah jeda sebentar.

## 13. Catatan kontribusi anggota (Kelompok 3)

### Seksi pekerjaan

| Seksi | Pekerjaan |
|---|---|
| 1 | Perancangan use case, parameter, dan exit code |
| 2 | Setup repository, struktur folder, `.gitignore`, Git dan SSH |
| 3 | Modul parameter dan validasi (`usage`, `parse_args`, `validate_input`) |
| 4 | Modul logging (`log`, `init_log`) |
| 5 | Modul inti backup (`create_backup`, `verify_backup`) |
| 6 | Modul konfigurasi (`load_config`, `config/backup.conf.example`) |
| 7 | Pengujian (`tests/run_tests.sh`, `evidence/`) |
| 8 | Dokumentasi (README) |
| 9 | Review keamanan dan kualitas script |
| 10 | Verifikasi reproduksi di mesin lain |
| 11 | Catatan kontribusi |
| 12 | Rilis (tag Git) dan submission |

### Penanggung jawab

| No | Anggota | Seksi | Kontribusi |
|---|---|---|---|
| 1 | Aqshal Seta Pameling | 4 | Penanggung jawab modul logging; menyediakan tempat (kos) untuk pengerjaan bersama |
| 2 | Adibta Ilham Winanta | 1, 2, 3 | Menyediakan laptop dan VM untuk penulisan dan pengujian; menjalankan setup repository |
| 3 | Bayu Faqih Alqurni | 7 | Penanggung jawab pengujian |
| 4 | Belmirel Ilavi R.U | 5, 12 | Penanggung jawab modul inti backup, rilis, dan submission |
| 5 | Jahran Pahlevi Tambrin | 8, 9 | Penanggung jawab dokumentasi dan review keamanan |
| 6 | Muhammad Rakha B. Ardan | 10, 11 | Penanggung jawab verifikasi reproduksi dan catatan kontribusi |
| 7 | Zaidaan Satrya H | 6 | Penanggung jawab modul konfigurasi |

### Status

- Seksi 1 sampai 11: selesai dan sudah ada di repository (bukti seksi 9 dan 10 ada di `evidence/`).
- Seksi 12: pemasangan tag dan submission dilakukan setelah catatan ini di-commit.

### Catatan

- Pengerjaan dilakukan bersama-sama di tempat yang disediakan Aqshal (kos), dengan
  laptop dan VM milik Adibta. Karena itu hanya satu akun GitHub (`aipxd`) yang dipakai
  dan seluruh commit hingga saat ini berasal dari akun tersebut.

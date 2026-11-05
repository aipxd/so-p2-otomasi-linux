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
| `tests/run_tests_p12.sh` | Pengujian P12: kirim lewat SFTP (positif, negatif, pemeriksaan akses) |
| `evidence/` | Hasil nyata pengujian (`hasil_tes.txt`) dan log tiap skenario |
| `evidence/p12/` | Bukti P12: hasil tes, log, data permission, cleanup dan rollback |
| `logs/` | Log saat script berjalan (tidak di-commit) |
| `docs/` | Analisis permission dan risiko, prosedur cleanup dan rollback P12 |

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
| 7 | Pengaturan jarak jauh (opsi -r) kurang atau tidak valid, termasuk izin kunci terlalu terbuka |
| 8 | Koneksi, login, atau pengiriman ke server gagal |
| 9 | Verifikasi hasil kirim gagal (unduh ulang gagal atau checksum berbeda) |

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

## 14. P12: Kirim arsip ke server lewat SFTP dengan kunci SSH

Checkpoint P12 melanjutkan repository dan modul P11 yang sama. Versi P11 ada di tag
`P2-CHECKPOINT-P11-v01` (commit `324a963`). Versi ini diberi tag `P2-CHECKPOINT-P12-v01`.

### 14.1 Perubahan alur dari P11

| Tahap | P11 | P12 dengan opsi `-r` |
|---|---|---|
| 1 | Validasi parameter dan folder | Sama |
| 2 | Buat arsip lokal | Periksa pengaturan jarak jauh dulu, lalu buat arsip lokal |
| 3 | Verifikasi arsip lokal | Sama |
| 4 | Selesai | Kirim ke `nama.part` di server, ganti nama setelah lengkap |
| 5 | | Unduh kembali arsip dari server dan bandingkan SHA-256 dengan arsip lokal |

Tanpa opsi `-r`, script berjalan persis seperti P11. Arsip lokal tetap tersimpan walau
pengiriman gagal.

### 14.2 Layanan dan kontrol akses

Layanan yang diintegrasikan: SSH berbasis kunci dan transfer file lewat SFTP.

1. Hanya kunci terdaftar yang diterima. Login password dimatikan untuk `backupuser`.
2. `authorized_keys` berpembatas `restrict,from="127.0.0.1,::1"`.
3. `ForceCommand internal-sftp -u 077`: hanya transfer file, tanpa terminal, file baru berizin 600.
4. `ChrootDirectory /home/backupuser`: `backupuser` terkurung di folder rumahnya.
5. Hanya folder `incoming` yang bisa ditulis.

### 14.3 Menyiapkan server (satu VM)

Dijalankan sebagai user dengan hak `sudo`. Tidak ada password atau private key di langkah ini.

```bash
# 1. user penerima backup (tanpa shell, password terkunci) dan folder tujuan
sudo adduser --disabled-password --gecos "" --shell /usr/sbin/nologin backupuser
sudo -u backupuser mkdir -p /home/backupuser/incoming
sudo chmod 700 /home/backupuser/incoming

# 2. pasangan kunci khusus backup (private key tetap di ~/.ssh, jangan ditampilkan)
ssh-keygen -t ed25519 -f ~/.ssh/backup_key -C "backup-kelompok3" -N ""

# 3. pasang public key untuk backupuser dengan pembatas
sudo mkdir -p /home/backupuser/.ssh
sudo chmod 700 /home/backupuser/.ssh
echo "restrict,from=\"127.0.0.1,::1\" $(cat ~/.ssh/backup_key.pub)" | sudo tee /home/backupuser/.ssh/authorized_keys > /dev/null
sudo chmod 600 /home/backupuser/.ssh/authorized_keys
sudo chown -R backupuser:backupuser /home/backupuser/.ssh

# 4. syarat chroot: folder rumah dimiliki root dan tidak bisa ditulis user
sudo chown root:backupuser /home/backupuser
sudo chmod 750 /home/backupuser
```

Lalu buat file `/etc/ssh/sshd_config.d/99-backupuser.conf` (angka 99 supaya blok `Match`
terbaca paling akhir) dengan isi:

```
# Pembatasan khusus untuk user backupuser (Proyek 2, P12)
Match User backupuser
    ChrootDirectory /home/backupuser
    ForceCommand internal-sftp -u 077
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    AllowTcpForwarding no
    X11Forwarding no
    AllowAgentForwarding no
    PermitTTY no
```

Periksa lalu terapkan (sesi SSH yang sedang berjalan tidak terputus):

```bash
sudo sshd -t && echo "sintaks OK"
sudo systemctl reload ssh
```

Pengaturan global SSH tidak diubah, jadi login akun admin tidak terpengaruh.

### 14.4 Konfigurasi

Kunci tambahan di file konfigurasi (contoh ada di `config/backup.conf.example`):

| Kunci | Arti |
|---|---|
| `REMOTE_HOST` | Alamat server (contoh: `localhost`) |
| `REMOTE_USER` | User penerima (contoh: `backupuser`) |
| `REMOTE_DIR` | Folder tujuan di server, path absolut tanpa spasi atau `..` (contoh: `/incoming`) |
| `REMOTE_PORT` | Port SSH, bawaan 22 |
| `SSH_KEY` | Path absolut file private key. Harus berizin 600, kalau tidak script berhenti (exit 7) |

Path `REMOTE_DIR` dilihat dari dalam kurungan chroot, sehingga `/incoming` adalah
`/home/backupuser/incoming` di server. File `config/backup.conf` yang asli tidak ikut
di-commit dan hanya berisi alamat serta path, tanpa credential.

### 14.5 Cara menjalankan

```bash
cp config/backup.conf.example config/backup.conf
# edit SRC_DIR, DEST_DIR, dan SSH_KEY (gunakan path absolut)
chmod 600 config/backup.conf
./backup.sh -c config/backup.conf -r
echo "exit code: $?"
```

Jika sukses, log memuat baris `Arsip terkirim` dan `Verifikasi jarak jauh OK (SHA-256: ...)`.

### 14.6 Pengujian P12

```bash
./tests/run_tests_p12.sh
```

Skrip membuat data uji sementara, menjalankan semua skenario, menyimpan hasilnya ke
`evidence/p12/`, lalu menghapus sendiri arsip uji yang dikirimnya dari server. Server
default: `backupuser@localhost` port 22 folder `/incoming` dengan kunci `~/.ssh/backup_key`
(dapat diubah lewat variabel `T_HOST`, `T_USER`, `T_PORT`, `T_DIR`, `T_KEY`).

| ID | Skenario | Hasil yang diharapkan |
|---|---|---|
| P01 | Kirim dengan kunci yang benar | Exit 0, arsip di server berizin 600, SHA-256 cocok |
| P02 | Tanpa `-r` | Exit 0, hanya backup lokal |
| N01 | Kunci salah | Exit 8 |
| N02 | User tidak ada di server | Exit 8 |
| N03 | Kunci backup dipakai untuk user lain | Exit 8 |
| N04 | Izin kunci 644 | Exit 7 |
| N05 | File kunci tidak ada | Exit 7 |
| N06 | Host tidak terjangkau | Exit 8 |
| N07 | Port salah | Exit 8 |
| N08 | Folder tujuan di server tidak ada | Exit 8 |
| N09 | Menulis di akar server | Exit 8 |
| N10 | `REMOTE_DIR` memuat `..` | Exit 7 |
| N11 | `REMOTE_DIR` bukan path absolut | Exit 7 |
| N12 | `REMOTE_DIR` memuat karakter berbahaya | Exit 7 |
| N13 | Opsi `-r` tanpa konfigurasi jarak jauh lengkap | Exit 7 |
| D01 | Login dengan password | Ditolak |
| D02 | Menjalankan perintah shell | Ditolak (hanya sftp) |
| D03 | Membaca file di luar folder backup | Ditolak (file tidak ditemukan) |
| D04 | User biasa membuka folder `backupuser` | Ditolak |

Hasil aktual pada VM: 28 pengecekan lulus, 0 gagal (`evidence/p12/hasil_tes_p12.txt`).
Tes P11 tetap lulus (11 pengecekan, `evidence/p12/regresi_tes_p11.txt`).
Skrip tes juga memeriksa bahwa isi private key tidak muncul di folder bukti.

### 14.7 Analisis, cleanup, dan rollback

- Analisis permission dan risiko: `docs/ANALISIS_P12.md`
- Prosedur cleanup dan rollback beserta hasil eksekusi: `docs/CLEANUP_ROLLBACK_P12.md`
- Riwayat perubahan: `CHANGELOG.md`

Private key dan isi `~/.ssh` tidak pernah ditampilkan, diunggah, atau disimpan di repository.

### 14.8 Batasan P12

- Server dan klien berada di satu VM, jadi belum diuji di jaringan nyata.
- `StrictHostKeyChecking=accept-new` menerima host key pada koneksi pertama.
- Kunci tidak memakai passphrase agar script bisa berjalan otomatis.
- Pemegang kunci bisa membaca dan menghapus arsip di folder `incoming`, bukan hanya menulis.
- Jalur verifikasi dengan checksum berbeda (exit 9) belum tercakup tes otomatis.
- Path sumber, tujuan, dan `REMOTE_DIR` tidak boleh mengandung spasi.
- Akun biasa di VM masih mengizinkan login password (pengaturan global sengaja tidak diubah).
- Belum ada penjadwalan otomatis dan rotasi arsip lama.

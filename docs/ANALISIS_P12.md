# Analisis Permission dan Risiko Keamanan (P12)

Data diambil dari VM pada 2026-11-05 dan tersimpan di `evidence/p12/data_permission.txt`.

## 1. Alur akses

- P11: `backup.sh` membuat arsip `.tar.gz` di folder lokal.
- P12 (opsi `-r`): setelah arsip lokal lolos verifikasi, arsip dikirim lewat SFTP ke user
  `backupuser` memakai kunci SSH `backup_key`, lalu diunduh kembali untuk membandingkan
  SHA-256 dengan arsip lokal.

Akses ke server dibatasi berlapis:

1. Hanya kunci terdaftar yang diterima (password dimatikan untuk `backupuser`).
2. `authorized_keys` berpembatas `restrict,from="127.0.0.1,::1"`.
3. Pengaturan sshd: `ForceCommand internal-sftp -u 077`, `ChrootDirectory /home/backupuser`,
   tanpa terminal dan tanpa forwarding.
4. Izin folder: hanya `backupuser` yang bisa menulis di `incoming`.

## 2. Analisis permission (kondisi aktual)

| Objek | Izin | Pemilik | Penilaian |
|---|---|---|---|
| `~/.ssh` | `drwx------` (700) | adibta | Hanya pemilik. Sesuai. |
| `~/.ssh/backup_key` | `-rw-------` (600) | adibta | Private key hanya terbaca pemilik. Sesuai. Script menolak kunci yang izinnya lebih terbuka (tes N04). |
| `~/.ssh/backup_key.pub` | `-rw-r--r--` (644) | adibta | Public key, aman dibaca umum. |
| `/home/backupuser` | `drwxr-x---` (750) | root:backupuser | Syarat chroot: dimiliki root dan tidak bisa ditulis user. Sesuai. |
| `/home/backupuser/incoming` | `drwx------` (700) | backupuser | Satu-satunya tempat tulis. User lain tidak bisa membuka (tes D04). |
| `/home/backupuser/.ssh` | `drwx------` (700) | backupuser | Sesuai. |
| `authorized_keys` | `-rw-------` (600) | backupuser | Sesuai. |
| `config/backup.conf` | `-rw-------` (600) | adibta | Berisi alamat dan path server. Tidak masuk Git (`.gitignore`). |
| `config/backup.conf.example` | `-rw-rw-r--` (664) | adibta | Contoh tanpa credential, izin longgar tidak berisiko. |
| Arsip hasil kirim di server | `-rw-------` (600) | backupuser | Hasil `internal-sftp -u 077`. File uji lama (`uji_kirim.txt`, 664) dibuat sebelum aturan ini, berisiko rendah karena folder 700, dibersihkan pada prosedur cleanup. |

Akun `backupuser`: shell `/usr/sbin/nologin`, password terkunci (status `L`), anggota grup
`backupuser` dan `users`.

## 3. Bukti pengujian akses

Seluruh pengujian (28 cek lulus) ada di `evidence/p12/hasil_tes_p12.txt`.

| Pengujian | Hasil | Artinya |
|---|---|---|
| P01 kunci benar | Diterima, arsip di server berizin 600, SHA-256 cocok | Akses yang diizinkan berjalan |
| N01 kunci salah | Exit 8, ditolak | Kunci tidak terdaftar tidak bisa masuk |
| N03 kunci backup untuk user lain | Exit 8, ditolak | Kunci hanya berlaku untuk `backupuser` |
| N02 user tidak ada | Exit 8, ditolak | |
| D01 login password | `Permission denied (publickey)` | Password dimatikan untuk `backupuser` |
| D02 perintah shell | `This service allows sftp connections only.` | Hanya transfer file |
| D03 baca `/etc/passwd` | `not found` | Dikurung di folder rumahnya |
| N09 tulis di akar server | Exit 8, ditolak | Hanya `incoming` yang bisa ditulis |
| D04 user biasa buka folder backup | `Permission denied` | User lain tidak bisa mengintip |
| N04 izin kunci 644 | Exit 7, ditolak script | Kunci longgar tidak dipakai |

## 4. Risiko dan rekomendasi

| No | Risiko | Tingkat | Mitigasi saat ini | Rekomendasi |
|---|---|---|---|---|
| 1 | Private key tanpa passphrase: siapa pun yang memegang file kunci bisa mengirim ke server | Sedang | Izin 600, `from=` hanya localhost, `restrict`, sftp-only, chroot | Rotasi kunci berkala, simpan kunci di tempat terlindungi, pakai passphrase dengan ssh-agent jika tidak harus otomatis |
| 2 | Pemegang kunci bisa membaca dan menghapus arsip di `incoming`, bukan hanya menulis | Sedang | Terkurung di folder rumahnya | Pisahkan kunci kirim dan kunci baca, simpan salinan kedua di tempat lain |
| 3 | `from=` hanya localhost | Rendah (demo satu VM) | Membatasi asal koneksi | Ganti ke alamat IP klien jika server dan klien di mesin berbeda |
| 4 | `StrictHostKeyChecking=accept-new` menerima host key saat koneksi pertama (rentan penyamaran pada koneksi pertama) | Sedang di jaringan nyata | Host key yang berubah ditolak | Isi `known_hosts` dengan fingerprint yang sudah diverifikasi, lalu pakai `StrictHostKeyChecking=yes` |
| 5 | Akun biasa (`adibta`) masih mengizinkan login password | Sedang | Tidak berlaku untuk `backupuser`; pengaturan global sengaja tidak diubah agar admin tidak terkunci | Setelah login kunci admin teruji, set `PasswordAuthentication no`, batasi dengan `AllowUsers`, pertimbangkan fail2ban |
| 6 | `backupuser` termasuk grup `users` | Rendah | Home berizin 750 untuk grup `backupuser` dan `incoming` 700, jadi grup `users` tidak punya akses | Keluarkan dari grup `users` jika tidak diperlukan |
| 7 | Isi log | Rendah | Log hanya memuat path, nama user, dan pesan sftp. Pemeriksaan keamanan bukti pada tes lulus (tidak ada isi kunci) | Atur izin file log dan rotasi |
| 8 | Penyisipan perintah lewat nilai konfigurasi | Rendah | Validasi regex ketat, config dibaca sebagai data (tidak dieksekusi), diuji di N10 sampai N12 | Pertahankan. Konsekuensinya path berspasi ditolak |
| 9 | Nama arsip berstempel per detik bisa bentrok | Rendah | Script menolak menimpa arsip lama | Tambahkan nomor urut atau pecahan detik |
| 10 | Klien dan server di satu VM | Batasan | | Uji ulang dengan dua VM. Pada jaringan nyata SSH mengenkripsi data selama transfer |

## 5. Keterbatasan pengujian

- Jalur verifikasi dengan hasil checksum berbeda (exit 9) belum tercakup tes otomatis.
- Tes dilakukan di satu VM, sehingga belum membuktikan perilaku di jaringan nyata.
- Belum ada penjadwalan otomatis dan rotasi arsip lama.

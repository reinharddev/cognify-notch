# Cognify Notch

Notch ala Dynamic Island untuk MacBook: arahkan kursor ke notch, lalu notch membuka panel berisi lagu yang sedang diputar, agenda, catatan cepat, tray file, timer belajar, cermin kamera, dan pintasan. Semua berjalan di Mac kamu; tidak ada akun dan tidak ada data yang dikirim ke pembuatnya.

**[Unduh versi terbaru (DMG)](https://github.com/reinharddev/cognify-notch/releases/latest)** · macOS 13 atau lebih baru · Apple Silicon dan Intel

Cognify Notch adalah bagian dari Cognify, aplikasi catatan dan belajar berbasis AI yang berjalan offline. Versi ini berdiri sendiri: tidak perlu memasang Cognify.

## Fitur

| Fitur | Keterangan |
|---|---|
| Lagu & video | Spotify, Apple Music, YouTube, VLC, dan lainnya. Putar, jeda, ganti lagu; geser dua jari di notch untuk lagu berikutnya. |
| Equalizer | Batang mengikuti suara yang diputar: kiri nada rendah, kanan nada tinggi. |
| Agenda | Acara hari ini dan besok dari app Kalender. |
| Catatan cepat | Tulis satu baris, tekan Enter. Tersimpan di tab Catatan. |
| Tray | Seret file ke notch untuk diparkir sementara: seret keluar, AirDrop, ganti nama. File tetap di tempat aslinya. |
| Timer belajar | Fokus 25 menit, istirahat 5 menit, jumlah sesi per hari. |
| Cermin | Pratinjau kamera depan. Kamera hanya menyala saat tab Cermin dibuka dan tidak merekam. |
| Pintasan | Jalankan Siri Shortcuts dengan satu klik. |
| Volume & kecerahan | Perubahan ditampilkan di notch. |
| Baterai & charger | Muncul saat charger dicolok atau dicabut, dan saat baterai tinggal 20% dan 10%. |
| AirPods & headphone | Nama dan baterai perangkat muncul saat suara pindah ke perangkat Bluetooth. |
| Shortcut ⌃⌥N | Buka notch dari keyboard dan langsung mengetik. Esc atau klik di luar notch menutupnya. |

Pengaturan ada di ikon notch di menu bar: nyalakan atau matikan tiap fitur, buka saat Mac dinyalakan, dan periksa update. Update dipasang otomatis lewat [Sparkle](https://sparkle-project.org).

## Izin macOS

| Izin | Dipakai untuk | Jika ditolak |
|---|---|---|
| Kalender | Agenda | Agenda kosong |
| Kamera | Cermin | Cermin tidak tampil |
| Audio dari app lain | Equalizer | Batang bergerak sebagai animasi biasa |

Suara hanya diubah menjadi tinggi batang di memori; tidak direkam, disimpan, atau dikirim.

## Cara kerja "lagu yang sedang diputar"

Sejak macOS 15.4, Apple hanya mengizinkan program milik Apple membaca lagu yang sedang diputar. Cognify Notch memuat library kecil (`Sources/CognifyMedia`) ke `/usr/bin/perl`, cara yang juga dipakai Boring Notch. Jika Apple menutup celah ini, bagian lagu disembunyikan dan fitur lain tetap berjalan.

## Build sendiri

Butuh Xcode 15 atau lebih baru.

```bash
./build.sh 1.0.0 --no-notarize
```

Hasilnya `dist/Cognify Notch.app` dan `dist/Cognify-Notch-1.0.0.dmg`. Tanpa sertifikat Developer ID, app ditandatangani ad-hoc: buka pertama kali dengan klik kanan, lalu Buka.

## Lisensi

[AGPL-3.0](LICENSE), sama dengan Cognify. Sparkle berlisensi MIT.

# Aplikasi Web "Moodle"


## Sekilas Tentang

Moodle adalah Learning Management System (LMS) gratis dan open-source yang dikembangkan oleh Martin Dougiamas menggunakan bahasa pemrograman PHP dan didistribusikan berdasarkan GNU General Public License (GNU GPL). Moodle digunakan untuk menyediakan lingkungan pembelajaran daring yang terpadu bagi pendidik, administrator, serta peserta didik. Versi pertama Moodle dirilis pada 20 Agustus 2002 dan pengembangannya masih terus dilakukan secara aktif di bawah Moodle HQ. Aplikasi moodle disediakan gratis untuk Android dan iOS.

## Instalasi

**Spesifikasi Server & Identitas Lingkungan**
- Penyedia VPS: Helipod (Region: ap-jakarta, Indonesia)
- Alamat IP Publik: 43.173.53.5
- Domain Aktif: moodle-kdjk2.my.id (A Record: 43.173.53.5), www.moodle-kdjk2.my.id
- Sistem Operasi: Ubuntu 24.04.4 LTS (Noble Numbat - 64-bit)
- Spesifikasi VM: 2 vCPU, 4 GB RAM, 60 GB SSD
- Web Server: Apache/2.4.58 (Ubuntu)
- Database Server: MariaDB Server 10.11.14
- Bahasa Pemrograman / Runtime: PHP 8.3.6 (NTS, OPcache aktif)
- Versi Moodle: Moodle 5.2.4+ (Build: 20261013 - Cabang stabil 5.2, bukan LTS)
- Protokol Keamanan: HTTPS (TLS 1.3) via Let's Encrypt RSA 3072-bit (Auto-Renew aktif)
- Status Autentikasi SSH & Firewall Saat Ini:
  Login SSH menggunakan public key ED25519 sudah terpasang dan berfungsi. Namun autentikasi password SSH pada server saat      ini masih aktif (belum dimatikan demi kehati-hatian). Firewall internal host (UFW) belum aktif (Status: inactive).
  Saat ini pengamanan port sepenuhnya bergantung pada Cloud Firewall Helipod yang telah dikonfigurasi membuka Port 22 (SSH),   Port 80 (HTTP), dan Port 443 (HTTPS).


## Konfigurasi (opsional)

Setting server tambahan yang diperlukan untuk meningkatkan fungsi dan kinerja aplikasi, misalnya:
- batas upload file
- batas memori
- dll

Plugin untuk fungsi tambahan
- login dengan Google/Facebook
- editor Markdown
- dll


##  Maintenance (opsional)

Setting tambahan untuk maintenance secara periodik, misalnya:
- buat backup database tiap pekan
- hapus direktori sampah tiap hari
- dll


## Otomatisasi (opsional)

Skrip shell untuk otomatisasi instalasi, konfigurasi, dan maintenance.


## Cara Pemakaian

- Tampilan aplikasi web
- Fungsi-fungsi utama
- Isi dengan data real/dummy (jangan kosongan) dan sertakan beberapa screenshot


## Pembahasan

- Pendapat anda tentang aplikasi web ini
    - kelebihan
    - kekurangan
- Bandingkan dengan aplikasi web lain yang sejenis


## Referensi

Cantumkan tiap sumber informasi yang anda pakai.

# Aplikasi Web "Moodle"

## Sekilas Tentang

Moodle adalah Learning Management System (LMS) gratis dan open-source yang dikembangkan oleh Martin Dougiamas menggunakan bahasa pemrograman PHP dan didistribusikan berdasarkan GNU General Public License (GNU GPL). Moodle digunakan untuk menyediakan lingkungan pembelajaran daring yang terpadu bagi pendidik, administrator, serta peserta didik. Versi pertama Moodle dirilis pada 20 Agustus 2002 dan pengembangannya masih terus dilakukan secara aktif di bawah Moodle HQ. Aplikasi moodle disediakan gratis untuk Android dan iOS.

## Instalasi

**Prasyarat**

- **Penyedia VPS:** Helipod (Region: ap-jakarta, Indonesia)
- **Spesifikasi VM:** 2 vCPU, 4 GB RAM, 60 GB SSD
- **Domain Aktif:** `moodle-kdjk2.my.id` (A Record: `43.173.53.5`), `www.moodle-kdjk2.my.id`
- **Sistem Operasi:** Ubuntu 24.04.4 LTS (Noble Numbat - 64-bit)
- **Cloud Firewall Helipod**: Port 22 (SSH), Port 80 (HTTP), dan Port 443 (HTTPS).
- **Login SSH**: public key ED25519
- **Web Server:** Apache/2.4.58 (Ubuntu)
- **Database Server:** MariaDB Server 10.11.14
- **Bahasa Pemrograman / Runtime:** PHP 8.3.6 (NTS, OPcache aktif)

**Proses Instalasi**

1. Login ke server lewat SSH.
   ```bash
   ssh ubuntu@moodle-kdjk2.my.id
   ```
2. Verifikasi fingerprint host ED25519 server `(SHA256:aYWZ+J1qLLF10GzNqsesyJmX+0mUz2lcXLcjKmhOw30)`.
3. Atur zona waktu ke WIB dan perbarui seluruh paket sistem.
   ```bash
   sudo timedatectl set-timezone Asia/Jakarta
   sudo apt update && sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y
   ```
4. Pasang paket LAMP stack serta dependensi lengkap Moodle.
   ```bash
   sudo DEBIAN_FRONTEND=noninteractive apt install -y \
       apache2 mariadb-server libapache2-mod-php \
       php php-cli php-mysql php-curl php-gd php-intl \
       php-mbstring php-xml php-zip php-soap \
       unzip git curl composer certbot python3-certbot-apache
   ```
5. Konfigurasi ServerName global pada Apache untuk menghilangkan peringatan `AH00558`.
   ```bash
   echo "ServerName localhost" | sudo tee /etc/apache2/conf-available/servername.conf
   sudo a2enconf servername
   sudo systemctl reload apache2
   ```
6. Terapkan hardening pada MariaDB secara otomatis.
   ```bash
   sudo mariadb << 'EOSQL'
   DELETE FROM mysql.user WHERE User='';
   DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
   DROP DATABASE IF EXISTS test;
   DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
   FLUSH PRIVILEGES;
   EOSQL
   ```
7. Buat kredensial acak untuk database dan admin Moodle. Pada server ini, kata sandi dibuat secara terprogram tanpa hardcode.
   ```bash
   DB_PASS=$(openssl rand -hex 16)
   # Format kombinasi awal yang dijalankan pada server untuk memenuhi kompleksitas Moodle:
   ADMIN_PASS="Moodle2026!$(openssl rand -hex 8)"

   sudo tee /root/moodle-credentials.txt << EOC
   DB_NAME=moodle
   DB_USER=moodleuser
   DB_PASS=${DB_PASS}
   ADMIN_USER=admin
   ADMIN_PASS=${ADMIN_PASS}
   EOC
   sudo chmod 600 /root/moodle-credentials.txt
   sudo chown root:root /root/moodle-credentials.txt
   ```
8. Buat database dengan encoding `utf8mb4` dan user dengan hak terbatas (prinsip *least privilege*):
   ```bash
   sudo mariadb -e "CREATE DATABASE IF NOT EXISTS moodle DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
   sudo mariadb -e "CREATE USER IF NOT EXISTS 'moodleuser'@'localhost' IDENTIFIED BY '${DB_PASS}';"
   sudo mariadb -e "GRANT SELECT,INSERT,UPDATE,DELETE,CREATE,CREATE TEMPORARY TABLES,DROP,INDEX,ALTER ON moodle.* TO 'moodleuser'@'localhost';"
   sudo mariadb -e "FLUSH PRIVILEGES;"
   ```
9. Unduh Moodle versi cabang stabil 5.2 (bukan LTS) lewat git.
   ```bash
   sudo git clone --depth 1 --branch MOODLE_502_STABLE https://github.com/moodle/moodle.git /var/www/moodle
   ```
10. Membuat direktori `moodledata` di luar *document root* web agar berkas materi dan tugas tidak bisa diakses langsung dari internet.
   ```bash
   sudo mkdir -p /var/moodledata
   sudo chown -R www-data:www-data /var/moodledata
   sudo chmod 770 /var/moodledata
   ```
11. Pasang dependensi PHP dengan Composer. Moodle versi 5.1 ke atas mewajibkan modul dependensi vendor.
    ```bash
    sudo chown -R www-data:www-data /var/www/moodle
    cd /var/www/moodle
    sudo -u www-data env COMPOSER_HOME=/tmp/composer composer install --no-dev --classmap-authoritative
    ```
12. Sesuaikan konfigurasi PHP untuk batas variabel formulir dan kuota berkas
    ```bash
    sudo tee /etc/php/8.3/apache2/conf.d/99-moodle.ini << 'EOF'
    max_input_vars = 5000
    upload_max_filesize = 100M
    post_max_size = 100M
    memory_limit = 256M
    EOF
    sudo cp /etc/php/8.3/apache2/conf.d/99-moodle.ini /etc/php/8.3/cli/conf.d/99-moodle.ini
    ```
13. Buat VirtualHost Apache yang mengarah ke direktori `/public`.
   ```bash
   sudo tee /etc/apache2/sites-available/moodle.conf << 'EOF'
   <VirtualHost *:80>
       ServerName moodle-kdjk2.my.id
       ServerAlias www.moodle-kdjk2.my.id
       DocumentRoot /var/www/moodle/public
       <Directory /var/www/moodle/public>
           AllowOverride None
           Require all granted
           DirectoryIndex index.php
           FallbackResource /r.php
       </Directory>
       ErrorLog ${APACHE_LOG_DIR}/moodle_error.log
       CustomLog ${APACHE_LOG_DIR}/moodle_access.log combined
   </VirtualHost>
   EOF

   sudo a2dissite 000-default
   sudo a2ensite moodle
   ```
14. Perbaiki router Moodle. `SetHandler` di `php8.3.conf` dibungkus dengan `<If "-f %{REQUEST_FILENAME}">` agar route virtual Moodle diproses via `/r.php`:
   ```bash
   sudo cp /etc/apache2/mods-available/php8.3.conf /root/php8.3.conf.bak
   sudo sed -i 's|^\(\s*\)SetHandler application/x-httpd-php$|\1<If "-f %{REQUEST_FILENAME}">\n\1    SetHandler application/x-httpd-php\n\1</If>|' /etc/apache2/mods-available/php8.3.conf
   sudo apache2ctl configtest
   sudo systemctl restart apache2
   ```
15. Tambahkan entri loopback `/etc/hosts` di server agar request dari server ke domainnya sendiri tidak keluar lewat IP publik.
   ```bash
   echo "127.0.0.1 moodle-kdjk2.my.id www.moodle-kdjk2.my.id" | sudo tee -a /etc/hosts
   ```
16. Jalankan installer Moodle lewat CLI.
   ```bash
   sudo -u www-data /usr/bin/php /var/www/moodle/admin/cli/install.php \
       --non-interactive \
       --agree-license \
       --wwwroot="https://moodle-kdjk2.my.id" \
       --dataroot="/var/moodledata" \
       --dbtype="mariadb" \
       --dbhost="localhost" \
       --dbname="moodle" \
       --dbuser="moodleuser" \
       --dbpass="${DB_PASS}" \
       --prefix="mdl_" \
       --fullname="LMS Kelompok 2" \
       --shortname="LMS-K2" \
       --adminuser="admin" \
       --adminpass="${ADMIN_PASS}" \
       --adminemail="<email>" \
       --lang="id"
   ```
17. Beri tahu Moodle bahwa router sudah dikonfigurasi, lalu kunci kembali izin kode sumber.
   ```bash
   sudo sed -i '/lib\/setup.php/i $CFG->routerconfigured = true;' /var/www/moodle/config.php
   sudo chown -R root:root /var/www/moodle
   sudo chmod 644 /var/www/moodle/config.php
   ```
18. Terbitkan sertifikat TLS dan mengaktifkan pengalihan HTTP -> HTTPS, lalu uji perpanjangan otomatisnya.
   ```bash
   sudo certbot --apache \
       -d moodle-kdjk2.my.id \
       -d www.moodle-kdjk2.my.id \
       --non-interactive \
       --agree-tos \
       -m "<email>" \
       --redirect
   sudo certbot renew --dry-run
   ```
19. Pasang cron Moodle agar tugas berjalan tiap menit.
   ```bash
   echo "* * * * * /usr/bin/php /var/www/moodle/admin/cli/cron.php >/dev/null" | sudo crontab -u www-data -
   ```
20. Verifikasi dari terminal
    ```bash
    curl -I http://moodle-kdjk2.my.id/
    curl -I https://moodle-kdjk2.my.id/
    curl -I https://moodle-kdjk2.my.id/login/index.php
    curl -I https://moodle-kdjk2.my.id/not/a/valid/request
    ```

## 3. Masalah Nyata yang Dialami & Solusinya

| No | Gejala Masalah | Lokasi Kejadian | Analisis Penyebab | Solusi yang Diterapkan |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Peringatan *Host Key Verification Failed* saat SSH | Laptop (Host) | Fingerprint server berubah setelah VPS di-reinstall | Membersihkan cache host key lama dengan `ssh-keygen -R 43.173.53.5` lalu memverifikasi fingerprint ED25519 baru. |
| 2 | Login SSH menggunakan password ditolak berkali-kali | VPS Helipod | Password root awal gagal dicocokkan oleh sistem login VPS | Melakukan reset password melalui tab *SSH* di dashboard Helipod, mengidentifikasi user default adalah `ubuntu`, lalu memasang public key laptop ke `authorized_keys`. |
| 3 | Kapasitas disk bawaan installer hanya teralokasi separuh | VM Lokal | Pengaturan bawaan LVM Ubuntu hanya memetakan 14 GB dari 30 GB | Menjalankan `sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv` untuk memperbesar partisi secara online (hanya terjadi di VM lokal). |
| 4 | Moodle menolak berjalan (*Vendor autoload not found*) | VM Lokal & VPS | Unduhan dari git clone tidak menyertakan folder dependensi pihak ketiga | Menjalankan `composer install --no-dev --classmap-authoritative` dengan hak akses user `www-data`. |
| 5 | Pemeriksaan status router di Moodle berstatus Galat (*Router Not Configured*) | VM Lokal & VPS | Handler PHP di Apache menangkap URL fiktif berekstensi `.php` sehingga `FallbackResource /r.php` tidak pernah terpanggil | Membungkus `SetHandler` di `/etc/apache2/mods-available/php8.3.conf` dengan evaluasi fisik file `<If "-f %{REQUEST_FILENAME}">`. |
| 6 | Muncul error 404 saat redirect admin pasca-instalasi | VM Lokal | Diduga Apache belum mengenali file index utama direktori sebelum melempar ke fallback (masih berupa dugaan) | Menambahkan arahan `DirectoryIndex index.php` sebelum `FallbackResource /r.php` pada VirtualHost (dialami di VM lokal). |
| 7 | Request curl dari dalam server ke domain sendiri sempat gagal | VPS Helipod | Request loopback diarahkan ke IP publik yang belum sepenuhnya melewati firewall | Menambahkan pemetaan lokal `127.0.0.1 moodle-kdjk2.my.id www.moodle-kdjk2.my.id` pada berkas `/etc/hosts` server sebagai *workaround*. |
| 8 | Port 443 tidak dapat diakses dari internet publik (*Connection Timed Out*) | Cloud VPS | Cloud Firewall bawaan pada panel Helipod belum meloloskan traffic masuk pada Port 443 | Menambahkan aturan TCP Port 443 (Allow dari `0.0.0.0/0`) pada tab Firewall di dashboard cloud Helipod. |

---

## 4. Hasil Verifikasi Akhir

### A. Pengujian HTTP & HTTPS Publik
- Request ke `http://moodle-kdjk2.my.id` berhasil dialihkan (*301 Moved Permanently*) ke `https://moodle-kdjk2.my.id/`.
- Request ke `https://moodle-kdjk2.my.id/` mengembalikan **HTTP/1.1 303 See Other** yang mengarah ke halaman login.
- Request ke `https://moodle-kdjk2.my.id/login/index.php` mengembalikan **HTTP/1.1 200 OK** dengan enkripsi SSL Let's Encrypt yang valid dan terpercaya.

### B. Pengujian Router Moodle
- Route test shim (`/lib/exampleshimroute2.php`): Mengembalikan **HTTP/1.1 302 Found**.
- Route fiktif (`/not/a/valid/request`): Mengembalikan **HTTP/1.1 404 Not Found**.
- Status perutean di laporan administrasi Moodle: **Lolos / OK**.

### C. Pengujian Backup
- Skrip `/usr/local/bin/moodle-backup.sh` berhasil dijalankan dan menghasilkan arsip terkompresi di `/var/backups/moodle/`:
  - Database terkompresi: `moodle-db-2026-10-18_1520.sql.gz` (176 KB)
  - Berkas moodledata: `moodledata-2026-10-18_1520.tar.gz` (1.2 MB)
- Uji simulasi perpanjangan berkala sertifikat (`sudo certbot renew --dry-run`) **berhasil 100% tanpa error**.
- **Catatan Evaluasi:** Pengujian proses pemulihan (*restore*) dari berkas cadangan ini **belum diuji** secara langsung pada lingkungan bersih.

---

## 5. Yang Belum Diuji (Outstanding / Pending Items)
1. **Restore Backup**: Pengujian pemulihan (*restore*) basis data MariaDB dari file `.sql.gz` dan direktori `moodledata` dari file `.tar.gz` belum pernah dicoba di lingkungan bersih.
2. **Restore Kursus (.mbz)**: Fitur pemulihan (*restore*) mata kuliah dummy dari file `.mbz` buatan anggota kelompok belum diimpor ke server live.
3. **Pengujian Skrip dari Server Kosong**: Skrip `install-moodle.sh` telah dirancang idempoten, namun belum pernah diuji eksekusinya secara menyeluruh dari kondisi OS kosongan baru (*clean install*).
4. **Pengerasan SSH & Host Firewall (UFW / Fail2ban)**: Penonaktifan login password (`PasswordAuthentication no`), pengaktifan firewall host (`UFW`), dan pemasangan `fail2ban` belum dijalankan di server karena ditunda hingga Moodle dipastikan stabil menjelang hari demo.


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

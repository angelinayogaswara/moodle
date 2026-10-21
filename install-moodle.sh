#!/usr/bin/env bash
# ==============================================================================
# Skrip Otomatisasi Instalasi Moodle 5.2 pada Ubuntu 24.04 LTS (Noble Numbat)
# Projek Akhir KDJK Kelompok 2 CS-IPB
#
# Status: Dirancang idempoten, belum diuji dari server kosong.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# 0. Pengecekan Sistem Operasi & Hak Akses
# ------------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] Skrip ini harus dijalankan dengan hak akses root (sudo)." >&2
   exit 1
fi

if [[ ! -f /etc/os-release ]] || ! grep -q 'ID=ubuntu' /etc/os-release || ! grep -q 'VERSION_ID="24.04"' /etc/os-release; then
   echo "[ERROR] Sistem operasi tidak didukung. Skrip ini hanya didukung pada Ubuntu 24.04 LTS (Noble Numbat)." >&2
   exit 1
fi

# ------------------------------------------------------------------------------
# 1. Konfigurasi Variabel Lingkungan (Wajib Disediakan Pengguna)
# ------------------------------------------------------------------------------
DOMAIN="${DOMAIN:?Variabel DOMAIN wajib diisi (contoh: export DOMAIN=moodle-kdjk2.my.id)}"
LE_EMAIL="${LE_EMAIL:?Variabel LE_EMAIL wajib diisi (contoh: export LE_EMAIL=admin@example.com)}"
SITE_NAME="${SITE_NAME:-LMS Kelompok 2}"
SITE_SHORT_NAME="${SITE_SHORT_NAME:-LMS-K2}"
SKIP_HTTPS="${SKIP_HTTPS:-0}"

CREDENTIALS_FILE="/root/moodle-credentials.txt"
MOODLE_DIR="/var/www/moodle"
MOODLEDATA_DIR="/var/moodledata"

echo "=== MEMULAI PROSES INSTALASI / VERIFIKASI MOODLE 5.2 ==="
echo "Target Domain    : ${DOMAIN}"
echo "Admin / LE Email : ${LE_EMAIL}"
echo "Nama Situs       : ${SITE_NAME}"
echo "========================================================"

# ------------------------------------------------------------------------------
# 2. Update Sistem & Konfigurasi Timezone
# ------------------------------------------------------------------------------
echo "[1/10] Memperbarui sistem dan mengatur timezone Asia/Jakarta..."
timedatectl set-timezone Asia/Jakarta || true
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt upgrade -y

# ------------------------------------------------------------------------------
# 3. Instalasi Paket Dependensi (LAMP + Ekstensi Moodle)
# ------------------------------------------------------------------------------
echo "[2/10] Memasang dependensi web server, database, PHP 8.3, composer, certbot..."
apt install -y \
    apache2 \
    mariadb-server \
    libapache2-mod-php \
    php \
    php-cli \
    php-mysql \
    php-curl \
    php-gd \
    php-intl \
    php-mbstring \
    php-xml \
    php-zip \
    php-soap \
    unzip \
    git \
    curl \
    composer \
    certbot \
    python3-certbot-apache

# Set global ServerName di Apache untuk menghilangkan peringatan AH00558
echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf
a2enconf servername >/dev/null 2>&1 || true

# ------------------------------------------------------------------------------
# 4. Pengamanan MariaDB & Setup Database Moodle
# ------------------------------------------------------------------------------
echo "[3/10] Mengonfigurasi MariaDB dan kredensial Moodle..."

# Generate password acak jika belum ada file kredensial
if [[ ! -f "$CREDENTIALS_FILE" ]]; then
    # Menghasilkan password acak yang memenuhi syarat kompleksitas Moodle
    DB_PASS=$(openssl rand -hex 16)
    ADMIN_PASS="$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9')!A1"
    cat > "$CREDENTIALS_FILE" << EOC
DB_NAME=moodle
DB_USER=moodleuser
DB_PASS=${DB_PASS}
ADMIN_USER=admin
ADMIN_PASS=${ADMIN_PASS}
EOC
    chmod 600 "$CREDENTIALS_FILE"
    chown root:root "$CREDENTIALS_FILE"
    echo "[INFO] Kredensial baru telah dibuat dan disimpan aman di ${CREDENTIALS_FILE} (chmod 600)."
else
    DB_PASS=$(grep '^DB_PASS=' "$CREDENTIALS_FILE" | cut -d= -f2-)
    ADMIN_PASS=$(grep '^ADMIN_PASS=' "$CREDENTIALS_FILE" | cut -d= -f2-)
    echo "[INFO] Menggunakan kredensial yang tersimpan di ${CREDENTIALS_FILE}."
fi

# Hardening MariaDB & pembuatan user/database
mariadb << 'EOSQL'
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOSQL

mariadb -e "CREATE DATABASE IF NOT EXISTS moodle DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mariadb -e "CREATE USER IF NOT EXISTS 'moodleuser'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mariadb -e "ALTER USER 'moodleuser'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mariadb -e "GRANT SELECT,INSERT,UPDATE,DELETE,CREATE,CREATE TEMPORARY TABLES,DROP,INDEX,ALTER ON moodle.* TO 'moodleuser'@'localhost';"
mariadb -e "FLUSH PRIVILEGES;"

# ------------------------------------------------------------------------------
# 5. Unduh Source Code Moodle & Direktori Data
# ------------------------------------------------------------------------------
echo "[4/10] Mengunduh Moodle MOODLE_502_STABLE dan membuat moodledata..."
if [[ ! -d "${MOODLE_DIR}/.git" ]]; then
    git clone --depth 1 --branch MOODLE_502_STABLE https://github.com/moodle/moodle.git "${MOODLE_DIR}"
fi

mkdir -p "${MOODLEDATA_DIR}"
chown -R www-data:www-data "${MOODLEDATA_DIR}"
chmod 770 "${MOODLEDATA_DIR}"

# ------------------------------------------------------------------------------
# 6. Instalasi Dependensi Composer (Wajib Moodle 5.1+)
# ------------------------------------------------------------------------------
echo "[5/10] Memasang dependensi Composer untuk Moodle..."
if [[ ! -f "${MOODLE_DIR}/vendor/autoload.php" ]]; then
    chown -R www-data:www-data "${MOODLE_DIR}"
    cd "${MOODLE_DIR}"
    sudo -u www-data env COMPOSER_HOME=/tmp/composer composer install --no-dev --classmap-authoritative
fi

# ------------------------------------------------------------------------------
# 7. Konfigurasi PHP (Tuning Persyaratan Moodle)
# ------------------------------------------------------------------------------
echo "[6/10] Mengonfigurasi parameter PHP 8.3..."
cat > /etc/php/8.3/apache2/conf.d/99-moodle.ini << 'EOF'
max_input_vars = 5000
upload_max_filesize = 100M
post_max_size = 100M
memory_limit = 256M
EOF
cp /etc/php/8.3/apache2/conf.d/99-moodle.ini /etc/php/8.3/cli/conf.d/99-moodle.ini

# ------------------------------------------------------------------------------
# 8. Konfigurasi Apache VirtualHost & Router Fix
# ------------------------------------------------------------------------------
echo "[7/10] Mengonfigurasi Apache VirtualHost dan menerapkan perbaikan Router Moodle..."

# Pembuatan VirtualHost dibungkus pengecekan agar tidak menimpa redirect HTTPS Certbot
if [[ ! -f /etc/apache2/sites-available/moodle.conf ]]; then
    cat > /etc/apache2/sites-available/moodle.conf << EOF
<VirtualHost *:80>
    ServerName ${DOMAIN}
    ServerAlias www.${DOMAIN}
    DocumentRoot ${MOODLE_DIR}/public
    <Directory ${MOODLE_DIR}/public>
        AllowOverride None
        Require all granted
        DirectoryIndex index.php
        FallbackResource /r.php
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/moodle_error.log
    CustomLog \${APACHE_LOG_DIR}/moodle_access.log combined
</VirtualHost>
EOF
    a2dissite 000-default >/dev/null 2>&1 || true
    a2ensite moodle >/dev/null 2>&1 || true
else
    echo "[INFO] File /etc/apache2/sites-available/moodle.conf sudah ada, pembuatan dilewati agar tidak menimpa konfigurasi SSL/redirect."
fi

# Router Fix di mod_php: cegah SetHandler mengeksekusi file php fiktif agar FallbackResource bekerja
if ! grep -q '<If "-f %{REQUEST_FILENAME}">' /etc/apache2/mods-available/php8.3.conf; then
    cp /etc/apache2/mods-available/php8.3.conf "/root/php8.3.conf.bak.$(date +%F)"
    sed -i 's|^\(\s*\)SetHandler application/x-httpd-php$|\1<If "-f %{REQUEST_FILENAME}">\n\1    SetHandler application/x-httpd-php\n\1</If>|' /etc/apache2/mods-available/php8.3.conf
fi

apache2ctl configtest
systemctl restart apache2

# Masukkan entri loopback ke /etc/hosts jika belum ada
if ! grep -q "${DOMAIN}" /etc/hosts; then
    echo "127.0.0.1 ${DOMAIN} www.${DOMAIN}" >> /etc/hosts
fi

# ------------------------------------------------------------------------------
# 9. Eksekusi Moodle CLI Installer
# ------------------------------------------------------------------------------
echo "[8/10] Memeriksa status instalasi core Moodle..."
WWW_PROTOCOL="https"
if [[ "${SKIP_HTTPS}" == "1" ]]; then
    WWW_PROTOCOL="http"
fi

if [[ ! -f "${MOODLE_DIR}/config.php" ]]; then
    chown -R www-data:www-data "${MOODLE_DIR}"
    sudo -u www-data /usr/bin/php "${MOODLE_DIR}/admin/cli/install.php" \
        --non-interactive \
        --agree-license \
        --wwwroot="${WWW_PROTOCOL}://${DOMAIN}" \
        --dataroot="${MOODLEDATA_DIR}" \
        --dbtype="mariadb" \
        --dbhost="localhost" \
        --dbname="moodle" \
        --dbuser="moodleuser" \
        --dbpass="${DB_PASS}" \
        --prefix="mdl_" \
        --fullname="${SITE_NAME}" \
        --shortname="${SITE_SHORT_NAME}" \
        --adminuser="admin" \
        --adminpass="${ADMIN_PASS}" \
        --adminemail="${LE_EMAIL}" \
        --lang="id"
fi

# Flag routerconfigured di config.php
if ! grep -q "routerconfigured" "${MOODLE_DIR}/config.php"; then
    sed -i '/lib\/setup.php/i $CFG->routerconfigured = true;' "${MOODLE_DIR}/config.php"
fi

# Kunci izin kode
chown -R root:root "${MOODLE_DIR}"
chmod 644 "${MOODLE_DIR}/config.php"

# ------------------------------------------------------------------------------
# 10. Konfigurasi HTTPS dengan Let's Encrypt (Certbot)
# ------------------------------------------------------------------------------
if [[ "${SKIP_HTTPS}" != "1" ]]; then
    echo "[9/10] Memasang / memverifikasi sertifikat SSL Certbot untuk ${DOMAIN}..."
    if [[ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
        certbot --apache -d "${DOMAIN}" -d "www.${DOMAIN}" \
            --non-interactive \
            --agree-tos \
            -m "${LE_EMAIL}" \
            --redirect
    else
        echo "[INFO] Sertifikat SSL Let's Encrypt untuk ${DOMAIN} sudah terpasang."
    fi
else
    echo "[9/10] Melewati pemasangan HTTPS (SKIP_HTTPS=1)."
fi

# ------------------------------------------------------------------------------
# 11. Konfigurasi Cron & Skrip Backup
# ------------------------------------------------------------------------------
echo "[10/10] Mengonfigurasi cron Moodle dan skrip backup..."

# Cron Moodle
echo "* * * * * /usr/bin/php ${MOODLE_DIR}/admin/cli/cron.php >/dev/null" | crontab -u www-data -

# Skrip Backup
cat > /usr/local/bin/moodle-backup.sh << 'EOF'
#!/bin/bash
set -euo pipefail

BACKUP_DIR=/var/backups/moodle
DATE=$(date +%F_%H%M)
mkdir -p "$BACKUP_DIR"

# Backup MariaDB
mariadb-dump --single-transaction moodle | gzip > "$BACKUP_DIR/moodle-db-$DATE.sql.gz"

# Backup moodledata tanpa direktori volatile
tar -czf "$BACKUP_DIR/moodledata-$DATE.tar.gz" \
    --exclude=moodledata/cache \
    --exclude=moodledata/localcache \
    --exclude=moodledata/temp \
    --exclude=moodledata/sessions \
    -C /var moodledata

# Hapus backup lebih dari 7 hari
find "$BACKUP_DIR" -type f -mtime +7 -delete

echo "Backup selesai: $DATE"
EOF
chmod +x /usr/local/bin/moodle-backup.sh

# Pasang jadwal backup root mingguan tiap Minggu jam 02:00
(crontab -l 2>/dev/null | grep -v "moodle-backup.sh" || true; echo "0 2 * * 0 /usr/local/bin/moodle-backup.sh >> /var/log/moodle-backup.log 2>&1") | crontab -

echo "========================================================"
echo "[SUKSES] Eksekusi Moodle 5.2 Selesai!"
echo "URL Situs    : ${WWW_PROTOCOL}://${DOMAIN}"
echo "Kredensial   : Disimpan di ${CREDENTIALS_FILE}"
echo "========================================================"

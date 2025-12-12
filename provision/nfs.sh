#!/bin/bash

#Configurar DNS 
sleep 5
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf > /dev/null
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf > /dev/null

apt-get update -qq
apt-get install -y git

#INSTALAR NFS
apt-get install -y nfs-kernel-server

#INSTALAR PHP-FPM + EXTENSIONES
apt-get install -y php-fpm php-mysql php-curl php-gd php-mbstring \
    php-xml php-xmlrpc php-soap php-intl php-zip netcat-openbsd

#CREAR DIRECTORIO COMPARTIDO PARA LA WEB
mkdir -p /var/www/html/webapp
chown -R www-data:www-data /var/www/html/webapp
chmod -R 755 /var/www/html/webapp

#EXPORTS NFS
cat > /etc/exports << 'EOF'
/var/www/html/webapp 192.168.20.11(rw,sync,no_subtree_check,no_root_squash)
/var/www/html/webapp 192.168.20.12(rw,sync,no_subtree_check,no_root_squash)
EOF

exportfs -a
systemctl restart nfs-kernel-server
systemctl enable nfs-kernel-server

#CONFIGURAR PHP-FPM PARA ESCUCHAR EN PUERTO 9000
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
PHP_FPM_CONF="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"

sed -i 's|listen = /run/php/php.*-fpm.sock|listen = 9000|' "$PHP_FPM_CONF"
sed -i 's|;listen.allowed_clients.*|listen.allowed_clients = 192.168.20.11,192.168.20.12|' "$PHP_FPM_CONF"

systemctl restart php${PHP_VERSION}-fpm
systemctl enable php${PHP_VERSION}-fpm

sleep 3
netstat -tlnp | grep 9000

#ESPERAR A QUE LA BASE DE DATOS ESTE LISTA
MAX_ATTEMPTS=60
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if nc -z 192.168.30.10 3306 2>/dev/null; then
        echo "Base de datos disponible"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    sleep 5
done

#DESCARGAR LA WEB DE LA PRACTICA LAMP
rm -rf /var/www/html/webapp/*
rm -rf /tmp/lamp

git clone https://github.com/josejuansanchez/iaw-practica-lamp.git /tmp/lamp

#Copiar contenido de la app PHP
cp -r /tmp/lamp/src/* /var/www/html/webapp/

#CONFIGURAR CONFIG.PHP AUTOMATICO
cat > /var/www/html/webapp/config.php << 'EOF'
<?php
define('DB_HOST', '192.168.30.10');
define('DB_NAME', 'lamp_db');
define('DB_USER', 'lamp_user');
define('DB_PASS', 'lamp_password');

$mysqli = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);

if ($mysqli->connect_error) {
    die("Error de conexion: " . $mysqli->connect_error);
}

$mysqli->set_charset("utf8mb4");
?>
EOF

# CREAR SCRIPT DE INSTALACION DE BASE DE DATOS
cat > /var/www/html/webapp/install.php << 'EOF'
<?php
define('DB_HOST', '192.168.30.10');
define('DB_NAME', 'lamp_db');
define('DB_USER', 'lamp_user');
define('DB_PASS', 'lamp_password');
EOF

#Crear info.php para diagnostico
cat > /var/www/html/webapp/info.php << 'EOF'
<?php
phpinfo();
?>
EOF

#AJUSTAR PERMISOS
chown -R www-data:www-data /var/www/html/webapp
chmod -R 755 /var/www/html/webapp

#Limpiar temporales
rm -rf /tmp/lamp
ls -lh /var/www/html/webapp/





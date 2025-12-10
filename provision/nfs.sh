#!/bin/bash
sleep 5

# Actualiza sistema y DNS
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf

echo "========================================="
echo "Configurando Servidor NFS y PHP-FPM"
echo "========================================="

# Actualizar sistema
apt-get update

# Instalar NFS Server
echo "📦 Instalando NFS Server..."
apt-get install -y nfs-kernel-server

# Instalar PHP-FPM y extensiones necesarias
echo "📦 Instalando PHP-FPM y extensiones..."
apt-get install -y php-fpm php-mysql php-curl php-gd php-mbstring \
    php-xml php-xmlrpc php-soap php-intl php-zip git unzip

# Instalar herramientas adicionales
apt-get install -y wget curl

# Crear directorio compartido para la aplicación web
echo "📁 Creando directorio compartido..."
mkdir -p /var/www/html/webapp
chown -R www-data:www-data /var/www/html/webapp
chmod -R 755 /var/www/html/webapp

# Configurar exports de NFS
echo "🔧 Configurando NFS exports..."
cat > /etc/exports << 'EOF'
/var/www/html/webapp 192.168.20.11(rw,sync,no_subtree_check,no_root_squash)
/var/www/html/webapp 192.168.20.12(rw,sync,no_subtree_check,no_root_squash)
EOF

# Aplicar configuración de exports
exportfs -a

# Reiniciar servicio NFS
systemctl restart nfs-kernel-server
systemctl enable nfs-kernel-server

# Configurar PHP-FPM para escuchar en todas las interfaces
echo "🔧 Configurando PHP-FPM..."
# Encontrar la versión de PHP instalada
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
PHP_FPM_CONF="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"

# Modificar el pool por defecto para escuchar en puerto TCP
sed -i 's/listen = \/run\/php\/php.*-fpm.sock/listen = 9000/' "$PHP_FPM_CONF"
sed -i 's/;listen.allowed_clients/listen.allowed_clients/' "$PHP_FPM_CONF"
sed -i 's/listen.allowed_clients = 127.0.0.1/listen.allowed_clients = 192.168.20.11,192.168.20.12/' "$PHP_FPM_CONF"

# Reiniciar PHP-FPM
systemctl restart php${PHP_VERSION}-fpm
systemctl enable php${PHP_VERSION}-fpm

# =========================================
# DESPLEGAR APLICACIÓN DE GESTIÓN DE USUARIOS
# =========================================
echo "🚀 Desplegando aplicación de gestión de usuarios..."

# Clonar el repositorio
cd /tmp
git clone https://github.com/josejuansanchez/iaw-practica-lamp.git

# Copiar archivos de la aplicación
cp -r /tmp/iaw-practica-lamp/src/* /var/www/html/webapp/

# Ajustar permisos
chown -R www-data:www-data /var/www/html/webapp
chmod -R 755 /var/www/html/webapp

# Crear archivo de configuración de base de datos
echo "🔧 Configurando conexión a base de datos..."
cat > /var/www/html/webapp/config.php << 'EOF'
<?php
// Configuración de la base de datos
define('DB_HOST', '192.168.30.10'); // HAProxy (Proxy de BD)
define('DB_NAME', 'lamp_db');
define('DB_USER', 'lamp_user');
define('DB_PASS', 'lamp_password');
define('DB_CHARSET', 'utf8mb4');

// Crear conexión PDO
try {
    $dsn = "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME . ";charset=" . DB_CHARSET;
    $options = [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES   => false,
    ];
    $pdo = new PDO($dsn, DB_USER, DB_PASS, $options);
} catch (PDOException $e) {
    error_log("Error de conexión a BD: " . $e->getMessage());
    die("Error de conexión a la base de datos. Por favor, contacte al administrador.");
}
?>
EOF

# Crear script de inicialización de base de datos
cat > /var/www/html/webapp/install.php << 'EOF'
<?php
// Script de instalación de la base de datos
define('DB_HOST', '192.168.30.10');
define('DB_NAME', 'lamp_db');
define('DB_USER', 'lamp_user');
define('DB_PASS', 'lamp_password');

try {
    $pdo = new PDO(
        "mysql:host=" . DB_HOST . ";charset=utf8mb4",
        DB_USER,
        DB_PASS,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );
    
    // Crear base de datos si no existe
    $pdo->exec("CREATE DATABASE IF NOT EXISTS " . DB_NAME . " CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
    $pdo->exec("USE " . DB_NAME);
    
    // Crear tabla usuarios si no existe
    $sql = "CREATE TABLE IF NOT EXISTS usuarios (
        id INT AUTO_INCREMENT PRIMARY KEY,
        nombre VARCHAR(100) NOT NULL,
        apellidos VARCHAR(100) NOT NULL,
        email VARCHAR(100) NOT NULL UNIQUE,
        telefono VARCHAR(20),
        fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_email (email),
        INDEX idx_nombre (nombre)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
    
    $pdo->exec($sql);
    
    echo "✅ Base de datos y tabla creadas correctamente\n";
    
    // Insertar datos de prueba
    $stmt = $pdo->prepare("INSERT IGNORE INTO usuarios (nombre, apellidos, email, telefono) VALUES (?, ?, ?, ?)");
    $stmt->execute(['Juan', 'García López', 'juan.garcia@example.com', '666111222']);
    $stmt->execute(['María', 'Martínez Sánchez', 'maria.martinez@example.com', '666222333']);
    $stmt->execute(['Pedro', 'Rodríguez Pérez', 'pedro.rodriguez@example.com', '666333444']);
    
    echo "✅ Datos de prueba insertados correctamente\n";
    
} catch (PDOException $e) {
    die("❌ Error: " . $e->getMessage() . "\n");
}
?>
EOF

# Ajustar permisos de los archivos de configuración
chown www-data:www-data /var/www/html/webapp/config.php
chown www-data:www-data /var/www/html/webapp/install.php
chmod 640 /var/www/html/webapp/config.php

# Crear página de información PHP para pruebas
cat > /var/www/html/webapp/info.php << 'EOF'
<?php
phpinfo();
?>
EOF

chown www-data:www-data /var/www/html/webapp/info.php

# Limpiar archivos temporales
rm -rf /tmp/iaw-practica-lamp

echo ""
echo "✅ ============================================="
echo "✅ Servidor NFS y PHP-FPM configurado correctamente"
echo "✅ ============================================="
echo ""
echo "📋 Información del servidor:"
echo "   - Directorio compartido: /var/www/html/webapp"
echo "   - PHP-FPM escuchando en: 192.168.20.10:9000"
echo "   - Versión PHP: $PHP_VERSION"
echo "   - Aplicación desplegada desde GitHub"
echo ""
echo "🔗 URLs de acceso (a través del balanceador):"
echo "   - Aplicación: http://localhost:8080/"
echo "   - PHP Info: http://localhost:8080/info.php"
echo ""
echo "⚠️  IMPORTANTE:"
echo "   - Ejecutar install.php después de que las BD estén listas"
echo "   - Comando: php /var/www/html/webapp/install.php"
echo ""
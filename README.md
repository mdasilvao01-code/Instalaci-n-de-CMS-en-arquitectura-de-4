# Proyecto de Infraestructura con Vagrant, MariaDB Galera, HAProxy, NFS, PHP-FPM y Nginx

## 📁 Contenido del repositorio GitHub

El repositorio incluirá:

- **Documento técnico `README.md`**
- **Fichero `Vagrantfile`**
- **Ficheros de provisionamiento**
  - provision/bd.sh
  - provision/bd2.sh
  - provision/proxybd.sh
  - provision/nfs.sh
  - provision/web.sh
  - provision/web2.sh
  - provision/bl.sh
- **Capturas de pantalla del funcionamiento de la aplicación** (carpeta `/screenshots`)

---

## 📌 Requisitos IMPRESCINDIBLES

### 📝 Documento técnico (README.md)

Debe contener:

### 1. Índice  
Listado de todas las secciones.

### 2. Introducción  
Explicar:

- Qué se va a construir.
- Qué tecnologías se van a utilizar.
- Descripción de la infraestructura.
- Explicación del direccionamiento IP.

### 3. Instalaciones y configuraciones paso a paso  
Explicar detalladamente:

- Configuración de cada máquina.
- Instalación de MariaDB Galera.
- Configuración del clúster.
- HAProxy como balanceador de BD.
- NFS + PHP-FPM como servidor compartido.
- Nginx como balanceador front-end.
- Los dos servidores web.

Debe incluir:

- Capturas de pantalla
- Código (trozos de configuración)
- Comandos usados  
- Explicaciones claras

### 4. Redacción impecable  
- No puede haber faltas de ortografía.  
- Expresión clara y técnica.  

---

## 🧩 Código del Vagrantfile

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "debian/bookworm64"

  # Base de datos 1 (MariaDB Galera Nodo 1)
  config.vm.define "db1Mario" do |db1|
    db1.vm.hostname = "db1Mario"
    db1.vm.network "private_network", ip: "192.168.40.11"
    db1.vm.provision "shell", path: "provision/bd.sh"
  end

  # Base de datos 2 (MariaDB Galera Nodo 2)
  config.vm.define "db2Mario" do |db2|
    db2.vm.hostname = "db2Mario"
    db2.vm.network "private_network", ip: "192.168.40.12"
    db2.vm.provision "shell", path: "provision/bd2.sh"
  end

  # Proxy de base de datos (HAProxy)
  config.vm.define "proxyBDMario" do |proxy|
    proxy.vm.hostname = "proxyBDMario"
    proxy.vm.network "private_network", ip: "192.168.30.10"
    proxy.vm.network "private_network", ip: "192.168.40.10"
    proxy.vm.provision "shell", path: "provision/proxybd.sh"
  end

  # Servidor NFS con PHP-FPM
  config.vm.define "serverNFSMario" do |nfs|
    nfs.vm.hostname = "serverNFSMario"
    nfs.vm.network "private_network", ip: "192.168.20.10"
    nfs.vm.network "private_network", ip: "192.168.30.11"
    nfs.vm.provision "shell", path: "provision/nfs.sh"
  end

  # Servidor Web 1
  config.vm.define "serverweb1Mario" do |web1|
    web1.vm.hostname = "serverweb1Mario"
    web1.vm.network "private_network", ip: "192.168.20.11"
    web1.vm.provision "shell", path: "provision/web.sh"
  end

  # Servidor Web 2
  config.vm.define "serverweb2Mario" do |web2|
    web2.vm.hostname = "serverweb2Mario"
    web2.vm.network "private_network", ip: "192.168.20.12"
    web2.vm.provision "shell", path: "provision/web2.sh"
  end

  # Balanceador Nginx front-end
  config.vm.define "balanceadorMario" do |bl|
    bl.vm.hostname = "balanceadorMario"
    bl.vm.network "private_network", ip: "192.168.10.10"
    bl.vm.network "private_network", ip: "192.168.20.13"
    bl.vm.network "forwarded_port", guest: 80, host: 8080
    bl.vm.provision "shell", path: "provision/bl.sh"
  end
end

```

## 🧩 Código del bl (balanceador)

```bash
#!/bin/bash
sleep 5

# Arregla el DNS
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf

# Actualizar sistema
apt-get update

# Instalar Nginx
apt-get install -y nginx

# Configurar Nginx como balanceador de carga
cat > /etc/nginx/sites-available/balancer << 'EOF'
upstream backend_servers {
    # Algoritmo de balanceo: round-robin (por defecto)
    # Otras opciones: least_conn, ip_hash
    
    server 192.168.20.11:80 max_fails=3 fail_timeout=30s;
    server 192.168.20.12:80 max_fails=3 fail_timeout=30s;
}

server {
    listen 80;
    server_name _;
    
    # Logs del balanceador
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    
    location / {
        proxy_pass http://backend_servers;
        
        # Headers para mantener información del cliente
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Health check endpoint (opcional)
    location /nginx-health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

# Habilitar el sitio
ln -sf /etc/nginx/sites-available/balancer /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Verificar configuración
nginx -t

# Reiniciar Nginx
systemctl restart nginx
systemctl enable nginx

```

## 🧩 Código del NFS (NFS)

```bash

#!/bin/bash
sleep 5

echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf

#ACTUALIZACION DEL SISTEMA
apt-get update -qq
apt-get install -y git

#INSTALAR NFS
apt-get install -y nfs-kernel-server

#INSTALA PHP-FPM + EXTENSIONES
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


#DESCARGAR LA WEB DE LA PRACTICA LAMP
rm -rf /var/www/html/webapp/*
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

#AJUSTAR PERMISOS
chown -R www-data:www-data /var/www/html/webapp
chmod -R 755 /var/www/html/webapp

```

## 🧩 Código del HAPROXY (haproxy)

```bash

#!/bin/bash
set -e
sleep 7

#proxyBBDD.sh - HAProxy para MySQL

#DNS
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf >/dev/null
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf >/dev/null


#Actualizar sistema
apt-get update

#Instalar HAProxy
apt-get install -y haproxy

#Configurar HAProxy para MariaDB
cat > /etc/haproxy/haproxy.cfg << 'EOF'
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    timeout connect 10s
    timeout client 1h
    timeout server 1h

# Frontend para MariaDB (puerto 3306)
# Escucha en TODAS las interfaces para recibir conexiones desde cualquier red
frontend mariadb_frontend
    bind *:3306
    mode tcp
    default_backend mariadb_backend

# Backend con los nodos del cluster Galera
backend mariadb_backend
    mode tcp
    balance roundrobin
    option tcp-check
    
    # Health check mas permisivo
    tcp-check connect
    
    server db1Mario 192.168.40.11:3306 check inter 5s rise 2 fall 3
    server db2Mario 192.168.40.12:3306 check inter 5s rise 2 fall 3

# Estadisticas de HAProxy
listen stats
    bind *:8080
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if TRUE
    stats auth admin:admin
EOF

#Habilitar HAProxy
systemctl enable haproxy

#Reiniciar HAProxy
systemctl restart haproxy

#Esperar a que HAProxy este listo
sleep 5

#Verificar estado
systemctl status haproxy --no-pager

```

## 🧩 Código del WEB (web1)

```bash

#!/bin/bash
sleep 5

#Actualiza sistema y DNS
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf

#Actualizar sistema
apt-get update

#Instalar Nginx y cliente NFS
apt-get install -y nginx nfs-common

#Crear punto de montaje para NFS
mkdir -p /var/www/html/webapp

#Montar el directorio NFS
mount -t nfs 192.168.20.10:/var/www/html/webapp /var/www/html/webapp

#Hacer el montaje permanente
echo "192.168.20.10:/var/www/html/webapp /var/www/html/webapp nfs defaults 0 0" >> /etc/fstab

#Configurar Nginx para usar PHP-FPM remoto
cat > /etc/nginx/sites-available/webapp << 'EOF'
server {
    listen 80;
    server_name _;
    
    root /var/www/html/webapp;
    index index.php index.html index.htm;
    
    # Logs especificos
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    
    location / {
        try_files $uri $uri/ /index.php?$args;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        # PHP-FPM en el servidor NFS (remoto)
        fastcgi_pass 192.168.20.10:9000;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
    
    location ~ /\.ht {
        deny all;
    }
}
EOF

#Habilitar el sitio
ln -sf /etc/nginx/sites-available/webapp /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

#Verificar configuracion de Nginx
nginx -t

#Reiniciar Nginx
systemctl restart nginx
systemctl enable nginx

```

## 🧩 Código del WEB (web2)

```bash

#!/bin/bash
sleep 5

#Actualiza sistema y DNS
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf

#Actualizar sistema
apt-get update

#Instalar Nginx y cliente NFS
apt-get install -y nginx nfs-common

#Crear punto de montaje para NFS
mkdir -p /var/www/html/webapp

#Montar el directorio NFS
mount -t nfs 192.168.20.10:/var/www/html/webapp /var/www/html/webapp

#Hacer el montaje permanente
echo "192.168.20.10:/var/www/html/webapp /var/www/html/webapp nfs defaults 0 0" >> /etc/fstab

#Configurar Nginx para usar PHP-FPM remoto
cat > /etc/nginx/sites-available/webapp << 'EOF'
server {
    listen 80;
    server_name _;
    
    root /var/www/html/webapp;
    index index.php index.html index.htm;
    
    # Logs especificos
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    
    location / {
        try_files $uri $uri/ /index.php?$args;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        # PHP-FPM en el servidor NFS (remoto)
        fastcgi_pass 192.168.20.10:9000;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
    
    location ~ /\.ht {
        deny all;
    }
}
EOF

#Habilitar el sitio
ln -sf /etc/nginx/sites-available/webapp /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

#Verificar configuracion de Nginx
nginx -t

#Reiniciar Nginx
systemctl restart nginx
systemctl enable nginx


```

## 🧩 Código del Base de datos (bd1)

```bash

#!/bin/bash
sleep 5

#DNS
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf

#Actualizar sistema
apt-get update -qq

#Instalar MariaDB Server y Galera
DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server mariadb-client galera-4 rsync

#Detener MariaDB para configurar Galera
systemctl stop mariadb

#Configurar Galera Cluster
cat > /etc/mysql/mariadb.conf.d/60-galera.cnf << 'EOF'
[mysqld]
binlog_format=ROW
default-storage-engine=innodb
innodb_autoinc_lock_mode=2
bind-address=0.0.0.0

# Galera Provider Configuration
wsrep_on=ON
wsrep_provider=/usr/lib/galera/libgalera_smm.so

# Galera Cluster Configuration
wsrep_cluster_name="galera_cluster"
wsrep_cluster_address="gcomm://192.168.40.11,192.168.40.12"

# Galera Synchronization Configuration
wsrep_sst_method=rsync

# Galera Node Configuration
wsrep_node_address="192.168.40.11"
wsrep_node_name="db1Mario"
EOF

# Inicializar el cluster 
galera_new_cluster

# Esperar a que el servicio este listo
sleep 15

#Verificar que MariaDB esta corriendo
systemctl status mariadb --no-pager

# Crear base de datos y usuario para la aplicacion
mysql << 'EOSQL'
-- Crear base de datos
CREATE DATABASE IF NOT EXISTS lamp_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Crear usuario para la aplicacion
CREATE USER IF NOT EXISTS 'mario'@'%' IDENTIFIED BY '1234';
GRANT ALL PRIVILEGES ON lamp_db.* TO 'mario'@'%';

-- Usuario para health checks de HAProxy 
CREATE USER IF NOT EXISTS 'haproxy'@'%' IDENTIFIED BY '';
GRANT USAGE ON *.* TO 'haproxy'@'%';

-- Crear usuario root remoto para administracion
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'root';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;

FLUSH PRIVILEGES;

-- Verificar usuarios creados
SELECT User, Host FROM mysql.user WHERE User IN ('mario', 'haproxy', 'root');
EOSQL

#Habilitar MariaDB en el arranque
systemctl enable mariadb
mysql -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null 

```

## 🧩 Código del Base de datos (bd2)

```bash

#!/bin/bash
set -e
sleep 7

#DNS
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf >/dev/null
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf >/dev/null

#Actualizar sistema
apt-get update -qq

#Instalar MariaDB Server y Galera
DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server mariadb-client galera-4 rsync

#Detener MariaDB para configurar Galera
systemctl stop mariadb

#Configurar Galera Cluster
cat > /etc/mysql/mariadb.conf.d/60-galera.cnf << 'EOF'
[mysqld]
binlog_format=ROW
default-storage-engine=innodb
innodb_autoinc_lock_mode=2
bind-address=0.0.0.0

# Galera Provider Configuration
wsrep_on=ON
wsrep_provider=/usr/lib/galera/libgalera_smm.so

# Galera Cluster Configuration
wsrep_cluster_name="galera_cluster"
wsrep_cluster_address="gcomm://192.168.40.11,192.168.40.12"

# Galera Synchronization Configuration
wsrep_sst_method=rsync

# Galera Node Configuration
wsrep_node_address="192.168.40.12"
wsrep_node_name="db2Mario"
EOF


#Iniciar MariaDB 
systemctl start mariadb

#Esperar sincronizacion
sleep 15
Verificar estado
systemctl status mariadb --no-pager

#Habilitar MariaDB en el arranque
systemctl enable mariadb
mysql -e "SHOW STATUS LIKE 'wsrep_%';" | grep -E "(wsrep_cluster_size|wsrep_cluster_status|wsrep_ready|wsrep_connected)" 







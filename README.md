# 📘 Proyecto de Infraestructura con Vagrant

## 📑 Índice
1. [Introducción del Proyecto](#introducción-del-proyecto)
2. [Arquitectura de la Infraestructura](#arquitectura-de-la-infraestructura)
3. [Direccionamiento IP Utilizado](#direccionamiento-ip-utilizado)
4. [Scripts de Provisionamiento](#scripts-de-provisionamiento)
   - 4.1 [Balanceador Nginx (bl.sh)](#41-balanceador-nginx-blsh)
5. [Vídeo Demostrativo](#vídeo-demostrativo)

---

## Introducción del Proyecto

Este proyecto despliega una infraestructura multi-nodo usando Vagrant y Debian Bookworm.  
El objetivo es simular un entorno de producción con alta disponibilidad, donde cada componente se distribuye en distintas máquinas virtuales para obtener redundancia, balanceo de carga y segmentación de servicios.

La infraestructura incluye:

- **Clúster de base de datos MariaDB Galera** (2 nodos)
- **Balanceo de carga de base de datos mediante HAProxy**
- **Servidor NFS junto a PHP-FPM**
- **Dos servidores web replicados**
- **Balanceador Nginx frontal**
- **Redes privadas separadas**
- **Provisionamiento automatizado mediante scripts Bash**

---

## Arquitectura de la Infraestructura

La arquitectura se compone de varias redes que permiten aislar servicios y mejorar la seguridad:

| Red | Función | Equipos |
|-----|---------|---------|
| 192.168.10.0/24 | Acceso frontal | Balanceador Nginx |
| 192.168.20.0/24 | Red Web | Web1, Web2, NFS |
| 192.168.30.0/24 | Red App / Proxy BD | NFS, HAProxy |
| 192.168.40.0/24 | Red Base de Datos | DB1, DB2, HAProxy |

Este diseño permite separar las capas de la aplicación y evita que componentes sensibles estén expuestos.

---

## Direccionamiento IP Utilizado

Cada máquina dispone de una IP concreta según su función:

- **Balanceador Nginx:**  
  - 192.168.10.10  
  - 192.168.20.13  

- **Servidor Web 1:**  
  - 192.168.20.11  

- **Servidor Web 2:**  
  - 192.168.20.12  

- **Servidor NFS:**  
  - 192.168.20.10  
  - 192.168.30.11  

- **HAProxy Proxy BD:**  
  - 192.168.30.10  
  - 192.168.40.10  

- **DB1 (Galera nodo 1):**  
  - 192.168.40.11  

- **DB2 (Galera nodo 2):**  
  - 192.168.40.12  

---

# Scripts de Provisionamiento

En esta sección se incluyen los scripts utilizados por Vagrant para provisionar los distintos servicios.

---

## 4.1 Balanceador Nginx (bl.sh)

### Explicación

Este script realiza las siguientes tareas:

- Configura los DNS del sistema.
- Actualiza los repositorios de Debian.
- Instala Nginx.
- Configura un **balanceador round-robin** dirigido a los dos servidores web.
- Agrega un endpoint de health-check.
- Habilita el sitio configurado.
- Reinicia y habilita el servicio Nginx.

---

### Código del Script Balanceador (bl)

```bash
#!/bin/bash
sleep 5

echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf

apt-get update
apt-get install -y nginx

cat > /etc/nginx/sites-available/balancer << 'EOF'
upstream backend_servers {
    server 192.168.20.11:80 max_fails=3 fail_timeout=30s;
    server 192.168.20.12:80 max_fails=3 fail_timeout=30s;
}

server {
    listen 80;
    server_name _;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    location / {
        proxy_pass http://backend_servers;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location /nginx-health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

ln -sf /etc/nginx/sites-available/balancer /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t

systemctl restart nginx
systemctl enable nginx

```

---

### Código del Script NFS (nfs)

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
---

### Código del Script HAPROXY (haproxy)

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

---

### Código del Script WEB (web1)

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
---

### Código del Script WEB (web2)

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

---

### Código del Script WEB (web2)

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

---

### Código del Script DB (db1)

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

---

### Código del Script DB (db2)

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

```





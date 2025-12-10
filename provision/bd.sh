#!/bin/bash

sleep 5

# Fix DNS
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf


echo "========================================="
echo "Configurando Base de Datos 1 (Nodo Galera 1)"
echo "========================================="

# Actualizar sistema
apt-get update

# Instalar MariaDB Server y Galera
apt-get install -y mariadb-server mariadb-client galera-4 rsync

# Detener MariaDB para configurar Galera
systemctl stop mariadb

# Configurar Galera Cluster
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

# Inicializar el cluster (solo en el primer nodo)
galera_new_cluster

# Esperar a que el servicio esté listo
sleep 10

# Crear base de datos y usuario para la aplicación
mysql << 'EOSQL'
CREATE DATABASE IF NOT EXISTS lamp_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'lamp_user'@'%' IDENTIFIED BY 'lamp_password';
GRANT ALL PRIVILEGES ON lamp_db.* TO 'lamp_user'@'%';

-- Usuario para health checks de HAProxy
CREATE USER IF NOT EXISTS 'haproxy'@'192.168.30.10' IDENTIFIED BY '';
GRANT USAGE ON *.* TO 'haproxy'@'192.168.30.10';

FLUSH PRIVILEGES;
EOSQL

# Habilitar MariaDB en el arranque
systemctl enable mariadb

echo ""
echo "✅ Base de Datos 1 configurada correctamente"
echo "   - Base de datos: lamp_db"
echo "   - Usuario: lamp_user"
echo "   - Cluster: galera_cluster"
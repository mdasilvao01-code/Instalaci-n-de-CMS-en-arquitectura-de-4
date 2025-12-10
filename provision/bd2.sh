#!/bin/bash
set -e
sleep 7


# Fix DNS
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf >/dev/null
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf >/dev/null

echo "========================================="
echo "Configurando Base de Datos 2 (Nodo Galera 2)"
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
wsrep_node_address="192.168.40.12"
wsrep_node_name="db2Mario"
EOF

# Esperar a que el nodo 1 esté listo
echo "⏳ Esperando 30 segundos para que db1 esté lista..."
sleep 30

# Iniciar MariaDB (se unirá al cluster automáticamente)
systemctl start mariadb

# Habilitar MariaDB en el arranque
systemctl enable mariadb

echo ""
echo "✅ Base de Datos 2 configurada correctamente"
echo "   - Nodo conectado al cluster galera_cluster"
#!/bin/bash
set -e
sleep 7

# proxyBBDD.sh - HAProxy para MySQL

# Fix DNS
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf >/dev/null
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf >/dev/null


echo "========================================="
echo "Configurando Proxy de Base de Datos (HAProxy)"
echo "========================================="

# Actualizar sistema
apt-get update

# Instalar HAProxy
apt-get install -y haproxy

# Configurar HAProxy para MariaDB
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
    timeout connect 5000
    timeout client 50000
    timeout server 50000

# Frontend para MariaDB (puerto 3306)
frontend mariadb_frontend
    bind *:3306
    mode tcp
    default_backend mariadb_backend

# Backend con los nodos del cluster Galera
backend mariadb_backend
    mode tcp
    balance roundrobin
    option mysql-check user haproxy
    
    server db1Mario 192.168.40.11:3306 check
    server db2Mario 192.168.40.12:3306 check

# Estadísticas de HAProxy (opcional)
listen stats
    bind *:8080
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if TRUE
EOF

# Crear usuario en MariaDB para health checks
# Este comando se ejecutará después de que los nodos estén disponibles
# Por ahora, reiniciamos HAProxy
systemctl restart haproxy
systemctl enable haproxy

echo "✓ Proxy de Base de Datos configurado correctamente"
echo "Nota: Crear usuario 'haproxy'@'192.168.30.10' en MariaDB manualmente"
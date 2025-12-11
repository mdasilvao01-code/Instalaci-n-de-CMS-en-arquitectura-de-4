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



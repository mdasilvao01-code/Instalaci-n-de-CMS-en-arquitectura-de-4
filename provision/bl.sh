#!/bin/bash
sleep 5

# Fix DNS
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf


echo "========================================="
echo "Configurando Balanceador de Carga Frontend"
echo "========================================="

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

echo "✓ Balanceador de carga configurado correctamente"
echo "Backend servers: 192.168.20.11, 192.168.20.12"
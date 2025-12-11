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

# Habilitar el sitio
ln -sf /etc/nginx/sites-available/webapp /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Verificar configuracion de Nginx
nginx -t

# Reiniciar Nginx
systemctl restart nginx
systemctl enable nginx

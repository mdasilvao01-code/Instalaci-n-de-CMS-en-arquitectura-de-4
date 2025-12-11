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



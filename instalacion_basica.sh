#!/bin/bash



# Comprobación de privilegios (debe ejecutarse como root o con sudo)
if [ "$(id -u)" -ne 0 ]; then
  echo "Este script debe ejecutarse con privilegios de root."
  exit 1
fi

# Verificar si Docker está instalado
if ! command -v docker &> /dev/null; then
  echo "❌ Docker no está instalado. Instalándolo..."
  curl -sSL https://get.docker.com | sh
  systemctl enable docker
  usermod -aG docker $USER
  systemctl start docker
fi

# Verificar si docker-compose está instalado
if ! command -v docker-compose &> /dev/null; then
  echo "❌ docker-compose no está instalado. Instalándolo..."
  sudo apt install -y docker-compose || { echo "Error al instalar docker-compose"; exit 1; }
fi

# Instalación Adguard

# Verificar si el contenedor adguard-home ya existe
if docker ps -a --format '{{.Names}}' | grep -q "^adguard-home$"; then
  echo "✅ El contenedor 'adguard-home' ya existe. Saltando la creación."
  exit 0
fi

# Instalación Adguard

# 1. Crear carpetas necesarias
mkdir -p ./adguard/config ./adguard/workingdir
cd ./adguard || exit 1

# 2. Crear docker-compose.yml
echo "Creando docker-compose.yml para adguard..."
cat <<EOF > docker-compose.yml
services:
    adguardhome:
        container_name: adguard-home
        environment:
            - TZ=Europe/Madrid
        volumes:
            - ./config:/opt/adguardhome/conf
            - ./workingdir:/opt/adguardhome/work
        restart: always
        network_mode: host
        image: adguard/adguardhome
EOF

# 3. Ejecutar docker-compose ya con la config lista
echo "Levantando el contenedor con la configuración final..."
docker-compose up -d

echo "✅ ¡Adguard está listo! Accede a la interfaz web en http://localhost:3000"

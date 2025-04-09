#!/bin/bash

# Verificar si Docker está instalado
if ! command -v docker &> /dev/null; then
  echo "❌ Docker no está instalado. Instalándolo..."
  curl -sSL https://get.docker.com | sh
  sudo systemctl enable docker
  sudo usermod -aG docker $USER
  sudo systemctl start docker
fi

# Verificar si docker-compose está instalado
if ! command -v docker-compose &> /dev/null; then
  echo "❌ docker-compose no está instalado. Instalándolo..."
  sudo apt install -y docker-compose || { echo "Error al instalar docker-compose"; exit 1; }
fi
# 1. Crear carpetas necesarias
mkdir ./adguard
cd ./adguard
mkdir config && mkdir workingdir
cd ..
mkdir -p ./wireguard-docker
cd ./wireguard-docker || exit

# 2.Solicitar WG_HOST justo después del paso 1
read -rp "Introduce el dominio o IP pública para WireGuard (WG_HOST): " WG_HOST

# 3. Solicitar contraseña
read -sp "Introduce la nueva contraseña para el acceso a la interfaz: " NEW_PASSWORD
echo

# 4. Crear hash
PASSWORD_HASH=$(sudo docker run --rm ghcr.io/wg-easy/wg-easy wgpw $NEW_PASSWORD)

# 5. Escapar los $
ESCAPED_HASH=$(echo "$PASSWORD_HASH" | sed 's/PASSWORD_HASH=//g' | sed 's/\$/\$\$/g' | sed "s/'//g")

echo "Hash de la contraseña: $ESCAPED_HASH"

# 6. Crear archivo .env con toda la configuración
cat <<EOF > .env
$ESCAPED_HASH
WG_HOST=$WG_HOST
WG_PORT=51820
EOF

# 7. Crear docker-compose.yml
echo "Creando docker-compose.yml para wg-easy..."
cat <<EOF > docker-compose.yml

networks:
  wg_net:
    driver: bridge

services:
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy
    container_name: wg-easy
    restart: unless-stopped
    environment:
      - PASSWORD_HASH=${ESCAPED_HASH}
      - WG_HOST=${WG_HOST}
      - WG_PORT=$WG_PORT
    ports:
      - "$WG_PORT:$WG_PORT/udp"
      - "51821:51821/tcp"  # Interfaz web
    volumes:
      - ./:/etc/wireguard
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
    networks:
      - wg_net


adguardhome:
    container_name: adguard-home
    image: adguard/adguardhome
    environment:
      - TZ=Europe/Madrid
    volumes:
      - ./config:/opt/adguardhome/conf
      - ./workingdir:/opt/adguardhome/work
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "3000:3000/tcp"
      - "80:80/tcp"
      - "443:443/tcp"
    restart: always
    networks:
      - wg_net
EOF


# 8. Ejecutar docker-compose ya con la config lista
echo "Levantando el contenedor con la configuración final..."
sudo docker-compose up -d

echo "✅ ¡WireGuard está listo! Accede a la interfaz web !"
echo "✅ ¡Adguard está listo! Accede a la interfaz web"

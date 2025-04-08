#!/bin/bash

# 1. Crear carpetas necesarias

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
  vpn_net:
    driver: bridge
    
services:
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy
    container_name: wg-easy
    restart: unless-stopped
    environment:
      - PASSWORD_HASH=${ESCAPED_HASH}
      - WG_HOST=${WG_HOST}
      - WG_PORT=51820
    ports:
      - "51820:51820/udp"
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
      - vpn_net
    restart: always
EOF

# 8. Ejecutar docker-compose ya con la config lista
echo "Levantando el contenedor con la configuración final..."
sudo docker-compose up -d

echo "✅ ¡WireGuard está listo! Accede a la interfaz web !"

# Instalación Adguard

# 1. Crear carpetas necesarias
cd
mkdir ./adguard
cd ./adguard
mkdir config && mkdir workingdir || exit

# 2. Crear docker-compose.yml
echo "Creando docker-compose.yml para adguard..."
cat <<EOF > docker-compose.yml

services:
    adguardhome:
        container_name: adguard-home
        environment:
            - TZ=Europe/Madrid
        ports:
            - "3000:3000"     # Interfaz web
            - "53:53/tcp"     # DNS TCP
            - "53:53/udp"     # DNS UDP
        volumes:
            - ./config:/opt/adguardhome/conf
            - ./workingdir:/opt/adguardhome/work
        restart: always
        networks:
            - vpn_net
        image: adguard/adguardhome
EOF

# 8. Ejecutar docker-compose ya con la config lista
echo "Levantando el contenedor con la configuración final..."
sudo docker-compose up -d

echo "✅ ¡Adguard está listo! Accede a la interfaz web"

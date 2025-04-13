#!/bin/bash

# =====================
#  Verificación root
# =====================
if [ "$(id -u)" -ne 0 ]; then
  echo "Este script debe ejecutarse con privilegios de root."
  exit 1
fi

# =====================
#  Actualización del sistema
# =====================
echo "Actualizando los paquetes del sistema..."
apt update && apt upgrade -y

# =====================
#  Docker
# =====================
echo "Verificando Docker..."
if ! command -v docker &> /dev/null; then
  echo "❌ Docker no está instalado. Instalándolo..."
  curl -sSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
  usermod -aG docker "$SUDO_USER"
  echo "⚠️ Reinicia la sesión del usuario para usar Docker sin sudo."
fi

# =====================
#  Docker Compose
# =====================
echo "Verificando docker-compose..."
if ! command -v docker-compose &> /dev/null; then
  echo "❌ docker-compose no está instalado. Instalándolo..."
  apt install -y docker-compose || { echo "Error al instalar docker-compose"; exit 1; }
fi

# =====================
#  AdGuard Home
# =====================
echo "Configurando AdGuard Home..."
if docker ps -a --format '{{.Names}}' | grep -q "^adguard-home$"; then
  echo "✅ El contenedor 'adguard-home' ya existe. Saltando la creación."
else
  mkdir -p ./adguard/config ./adguard/workingdir
  cd ./adguard || exit 1
  echo "Creando docker-compose.yml para AdGuard..."
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
  docker-compose up -d
  cd ..
  echo "✅ ¡AdGuard está listo! Accede a la interfaz web en http://localhost:3000"
fi

# =====================
# Configuración de DNS para AdGuard Home
# =====================
echo "Configurando DNS para AdGuard Home..."

# Crear el directorio si no existe
mkdir -p /etc/systemd/resolved.conf.d

# Crear el archivo de configuración para desactivar DNSStubListener y establecer DNS a 127.0.0.1
tee /etc/systemd/resolved.conf.d/adguardhome.conf > /dev/null <<EOF
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
EOF


# Respaldar el archivo resolv.conf existente si no existe
if [ -f /etc/resolv.conf ]; then
  mv /etc/resolv.conf /etc/resolv.conf.backup
fi

# Crear un enlace simbólico para que systemd use el resolv.conf adecuado
ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf

# Reiniciar el servicio de systemd-resolved para aplicar los cambios
systemctl restart systemd-resolved

echo "✅ DNS configurado correctamente para AdGuard Home."


wget https://raw.githubusercontent.com/Bilito/wireguard/refs/heads/main/wireguard.sh
chmod +x wireguard.sh
./wireguard.sh

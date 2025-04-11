#!/bin/bash

# Actualización de paquetes del sistema
echo "Actualizando los paquetes del sistema..."
apt update && apt upgrade -y


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

# Comprobación de privilegios (debe ejecutarse como root o con sudo)
if [ "$(id -u)" -ne 0 ]; then
  echo "Este script debe ejecutarse con privilegios de root."
  exit 1
fi


read -p "Introduce el dominio DDNS o IP pública para el endpoint del servidor (ej. midominio.ddns.net): " ENDPOINT


# Instalación de WireGuard y sus herramientas
echo "Instalando WireGuard..."
apt install -y wireguard qrencode

# Generar claves para el servidor
echo "Generando claves para el servidor..."
wg genkey | tee /etc/wireguard/server_privatekey | wg pubkey > /etc/wireguard/server_publickey

# Configuración inicial del servidor
SERVER_CONF="/etc/wireguard/wg0.conf"
cat <<EOF > $SERVER_CONF
[Interface]
PrivateKey = $(cat /etc/wireguard/server_privatekey)
Address = 10.6.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE
EOF

# Función para agregar un peer
add_peer() {
  # Pedir al usuario el nombre del peer
  read -p "Introduce el nombre del peer (por ejemplo, 'Cliente1'): " PEER_NAME

  # Generar claves para el cliente
  echo "Generando claves para el cliente '$PEER_NAME'..."
  wg genkey | tee /etc/wireguard/${PEER_NAME}_privatekey | wg pubkey > /etc/wireguard/${PEER_NAME}_publickey
  
  # Obtener IP local de la interfaz principal
LOCAL_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')

  # Crear la configuración para el cliente
  CLIENT_CONFIG_PATH="/etc/wireguard/${PEER_NAME}_config.conf"
  cat <<EOF > $CLIENT_CONFIG_PATH
[Interface]
PrivateKey = $(cat /etc/wireguard/${PEER_NAME}_privatekey)
Address = 10.6.0.2/32
DNS = $LOCAL_IP

[Peer]
PublicKey = $(cat /etc/wireguard/server_publickey)
Endpoint = $ENDPOINT:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

  # Agregar la configuración del peer al archivo del servidor
  CLIENT_PUBLIC_KEY=$(cat /etc/wireguard/${PEER_NAME}_publickey)
  echo "[Peer]" >> $SERVER_CONF
  echo "# Nombre del Peer: $PEER_NAME" >> $SERVER_CONF
  echo "PublicKey = $CLIENT_PUBLIC_KEY" >> $SERVER_CONF
  echo "AllowedIPs = 10.6.0.2/32" >> $SERVER_CONF
  echo "" >> $SERVER_CONF

  # Generar código QR de la configuración del cliente
  echo "Generando código QR para la configuración del cliente '$PEER_NAME'..."
  qrencode -t png -o /etc/wireguard/${PEER_NAME}_config_qr.png < $CLIENT_CONFIG_PATH
  echo "Código QR guardado en: /etc/wireguard/${PEER_NAME}_config_qr.png"

  # Mostrar código QR por terminal
  echo "Código QR para '$PEER_NAME':"
  qrencode -t ansiutf8 < $CLIENT_CONFIG_PATH
  
  # Instrucción al usuario
  echo "Archivo de configuración del cliente '$PEER_NAME' guardado en: $CLIENT_CONFIG_PATH"
  echo "Código QR guardado en: /etc/wireguard/${PEER_NAME}_config_qr.png"
}

# Función principal para gestionar múltiples peers
while true; do
  add_peer

  # Preguntar si se desea agregar otro peer
  read -p "¿Deseas agregar otro peer? (s/n): " ADD_MORE
  if [[ "$ADD_MORE" != "s" && "$ADD_MORE" != "S" ]]; then
    break
  fi
done

# Habilitar reenvío de IP
echo "🛠️ Habilitando el reenvío de IP..."

if grep -q "^net.ipv4.ip_forward" /etc/sysctl.conf; then
  # Si la línea existe, la reemplazamos por la correcta
  sed -i 's/^net\.ipv4\.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/sysctl.conf
else
  # Si no existe, la agregamos al final
  echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
fi

# Aplicar cambios
sysctl -p



# Iniciar WireGuard
echo "Iniciando WireGuard..."
wg-quick up wg0

# Habilitar WireGuard para que se inicie al arrancar
echo "Habilitando WireGuard para que se inicie al arrancar..."
systemctl enable wg-quick@wg0

# Mostrar estado de la interfaz WireGuard
echo "Estado de la interfaz WireGuard:"
wg show

echo "WireGuard instalado y configurado correctamente."
echo "Recuerda compartir la configuración del cliente con los dispositivos que quieras conectar.

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

mkdir -p ./wireguard-docker
cd ./wireguard-docker || exit

echo "✅ ¡WireGuard está listo! Accede a la interfaz web !"

# Instalación Adguard

# 1. Crear carpetas necesarias
cd
mkdir ./adguard
cd ./adguard
mkdir config && mkdir workingdir || exit

echo "✅ ¡Adguard está listo! Accede a la interfaz web"

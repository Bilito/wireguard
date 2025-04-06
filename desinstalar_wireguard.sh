#!/bin/bash

# Navegamos hasta la carpeta adguard,  paramos el contenedor, volvemos atrás  y>

cd ./adguard
sudo docker-compose down
cd ..
sleep 1
sudo rm -rf ./adguard

# Navegamos hasta la carpeta wireguard,  paramos el contenedor, volvemos atrás >

cd ./wireguard-docker
sudo docker-compose down
sleep 1
cd ..
sleep 1
sudo rm -rf ./wireguard-docker

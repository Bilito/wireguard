#!/bin/bash

# Navegamos hasta la carpeta adguard,  paramos el contenedor, volvemos atrás  y elimininamos la carpeta

cd ./adguard
sudo docker-compose down
cd
sleep 3
sudo rm -R ./adguard 

# Navegamos hasta la carpeta wireguard,  paramos el contenedor, volvemos atrás  y elimininamos la carpeta
cd
sleep 3
cd ./wireguard-docker
sudo docker-compose down
cd
sleep 3
sudo rm -R ./wireguard-docker 


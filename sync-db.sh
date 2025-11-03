#!/bin/bash

echo "Sincronizando base de datos desde Digital Ocean..."

# Configuración
DO_HOST="tu-host-do.digitalocean.com"
DO_USER="tu-usuario"
DO_PASS="tu-contraseña"
DO_DB="tu-base-de-datos"
LOCAL_HOST="localhost"
LOCAL_USER="root"
LOCAL_PASS="password"
LOCAL_DB="laravel"

# Ejecutar sincronización
docker-compose run --rm mysql mysqldump -h $DO_HOST -u $DO_USER -p$DO_PASS $DO_DB | docker exec -i shared-mysql mysql -u $LOCAL_USER -p$LOCAL_PASS $LOCAL_DB

echo "Sincronización completada!" 
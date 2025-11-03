#!/bin/bash

# Configuración
DO_HOST="$1"
DO_USER="$2"
DO_PASS="$3"
DO_DB="$4"
LOCAL_HOST="$5"
LOCAL_USER="$6"
LOCAL_PASS="$7"
LOCAL_DB="$8"
TABLES="${@:9}"

echo "Sincronizando tablas específicas: $TABLES"

# Exportar solo las tablas especificadas
mysqldump -h $DO_HOST -u $DO_USER -p$DO_PASS $DO_DB $TABLES > /tmp/tables_backup.sql

# Importar a la base de datos local
mysql -h $LOCAL_HOST -u $LOCAL_USER -p$LOCAL_PASS $LOCAL_DB < /tmp/tables_backup.sql

echo "Sincronización de tablas completada: $(date)" 
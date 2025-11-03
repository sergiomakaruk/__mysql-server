#!/bin/bash

echo "Iniciando sincronización bajo demanda desde Digital Ocean a MySQL local..."

# Iniciar temporizador
START_TIME=$(date +%s)

# Función para confirmar la sincronización
confirm_sync() {
  read -p "¿Confirmas la sincronización de $DO_DB a $LOCAL_DB? (s/N): " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Ss]$ ]]; then
    echo "Sincronización cancelada."
    exit 0
  fi
}

# Función para mostrar el tiempo transcurrido
show_elapsed_time() {
  END_TIME=$(date +%s)
  ELAPSED=$((END_TIME - START_TIME))
  
  # Convertir segundos a formato horas:minutos:segundos
  HOURS=$((ELAPSED / 3600))
  MINUTES=$(( (ELAPSED % 3600) / 60 ))
  SECONDS=$((ELAPSED % 60))
  
  # Mostrar tiempo en formato adecuado
  if [ $HOURS -gt 0 ]; then
    echo "Tiempo total: ${HOURS}h ${MINUTES}m ${SECONDS}s"
  elif [ $MINUTES -gt 0 ]; then
    echo "Tiempo total: ${MINUTES}m ${SECONDS}s"
  else
    echo "Tiempo total: ${SECONDS}s"
  fi
}

# Si no se proporciona un nombre de base de datos, usar el valor por defecto o preguntar
if [ -z "$1" ]; then
  if [ -z "$DO_DB" ]; then
    read -p "Introduce el nombre de la base de datos en Digital Ocean: " DO_DB_INPUT
    DO_DB=$DO_DB_INPUT
  else
    echo "Usando base de datos: $DO_DB (configurada en .env)"
    read -p "¿Deseas cambiar la base de datos remota? (s/N): " CHANGE_DB
    if [[ "$CHANGE_DB" =~ ^[Ss]$ ]]; then
      read -p "Introduce el nombre de la base de datos remota: " DO_DB_INPUT
      DO_DB=$DO_DB_INPUT
    fi
  fi
else
  DO_DB=$1
  echo "Usando base de datos: $DO_DB (proporcionada como parámetro)"
fi

# Si no se proporciona un nombre de base de datos local, usar el valor por defecto o preguntar
if [ -z "$2" ]; then
  if [ -z "$LOCAL_DB" ]; then
    read -p "Introduce el nombre de la base de datos local: " LOCAL_DB_INPUT
    LOCAL_DB=$LOCAL_DB_INPUT
  else
    echo "Usando base de datos local: $LOCAL_DB (configurada en .env)"
    read -p "¿Deseas cambiar la base de datos local? (s/N): " CHANGE_LOCAL_DB
    if [[ "$CHANGE_LOCAL_DB" =~ ^[Ss]$ ]]; then
      read -p "Introduce el nombre de la base de datos local: " LOCAL_DB_INPUT
      LOCAL_DB=$LOCAL_DB_INPUT
    fi
  fi
else
  LOCAL_DB=$2
  echo "Usando base de datos local: $LOCAL_DB (proporcionada como parámetro)"
fi

# Mostrar resumen y pedir confirmación
echo "Resumen de la sincronización:"
echo "- Base de datos origen (Digital Ocean): $DO_DB"
echo "- Base de datos destino (Local): $LOCAL_DB"
confirm_sync

# Usar variables de entorno en lugar de parámetros
mysqldump -h $DO_HOST -P $DO_PORT -u $DO_USER -p$DO_PASS --ssl-mode=REQUIRED --set-gtid-purged=OFF --single-transaction --quick --lock-tables=false $DO_DB > /tmp/do_backup.sql

# Importar a la base de datos local
mysql -h $LOCAL_HOST -u $LOCAL_USER -p$LOCAL_PASS --force $LOCAL_DB < /tmp/do_backup.sql

echo "Sincronización completada: $(date)"
show_elapsed_time 
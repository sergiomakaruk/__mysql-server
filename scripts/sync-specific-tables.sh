#!/bin/bash

# Iniciar temporizador
START_TIME=$(date +%s)

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

# Usar variables de entorno
TABLES="$@"

echo "Sincronizando tablas específicas: $TABLES"

# Exportar solo las tablas especificadas
mysqldump -h $DO_HOST -P $DO_PORT -u $DO_USER -p$DO_PASS --ssl-mode=REQUIRED --set-gtid-purged=OFF $DO_DB $TABLES > /tmp/tables_backup.sql

# Importar a la base de datos local
mysql -h $LOCAL_HOST -u $LOCAL_USER -p$LOCAL_PASS $LOCAL_DB < /tmp/tables_backup.sql

echo "Sincronización de tablas completada: $(date)"
show_elapsed_time 
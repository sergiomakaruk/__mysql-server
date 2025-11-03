#!/bin/bash

# Asegurarse de que los contenedores estén en ejecución
docker-compose up -d mysql

# Verificar si se proporcionaron parámetros
if [ $# -eq 0 ]; then
  echo "Uso: ./do-sync.sh [base_de_datos_remota] [base_de_datos_local]"
  echo "Si no se proporcionan parámetros, se usarán los valores del archivo .env"
  
  # Ejecutar la sincronización con valores por defecto
  docker-compose run --rm sync-command /scripts/sync-on-demand.sh
else
  # Ejecutar la sincronización con los parámetros proporcionados
  docker-compose run --rm sync-command /scripts/sync-on-demand.sh "$@"
fi 
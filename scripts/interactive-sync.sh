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
    echo -e "${GREEN}Tiempo total: ${HOURS}h ${MINUTES}m ${SECONDS}s${NC}"
  elif [ $MINUTES -gt 0 ]; then
    echo -e "${GREEN}Tiempo total: ${MINUTES}m ${SECONDS}s${NC}"
  else
    echo -e "${GREEN}Tiempo total: ${SECONDS}s${NC}"
  fi
}

# Colores para mejor visualización
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Sincronización Interactiva de Base de Datos ===${NC}"
echo

# Mostrar bases de datos disponibles en Digital Ocean
echo -e "${YELLOW}Conectando a Digital Ocean para listar bases de datos disponibles...${NC}"
DATABASES=$(mysql -h $DO_HOST -P $DO_PORT -u $DO_USER -p$DO_PASS --ssl-mode=REQUIRED -e "SHOW DATABASES;" 2>/dev/null | grep -Ev "(Database|information_schema|performance_schema|mysql|sys)")

if [ $? -ne 0 ]; then
  echo -e "${RED}Error al conectar con Digital Ocean. Verifica tus credenciales.${NC}"
  exit 1
fi

echo -e "${GREEN}Bases de datos disponibles en Digital Ocean:${NC}"
echo "$DATABASES" | nl

# Seleccionar base de datos remota
if [ -z "$DO_DB" ]; then
  read -p "Introduce el número o nombre de la base de datos remota: " DB_SELECTION
  
  # Comprobar si es un número
  if [[ "$DB_SELECTION" =~ ^[0-9]+$ ]]; then
    DO_DB=$(echo "$DATABASES" | sed -n "${DB_SELECTION}p")
  else
    DO_DB=$DB_SELECTION
  fi
else
  echo -e "${YELLOW}Base de datos remota actual: ${GREEN}$DO_DB${NC}"
  # Solo preguntar si hay más de una base de datos disponible
  if [ $(echo "$DATABASES" | wc -l) -gt 1 ]; then
    read -p "¿Deseas cambiar la base de datos remota? (s/N): " CHANGE_DB
    if [[ "$CHANGE_DB" =~ ^[Ss]$ ]]; then
      read -p "Introduce el número o nombre de la base de datos remota: " DB_SELECTION
      
      # Comprobar si es un número
      if [[ "$DB_SELECTION" =~ ^[0-9]+$ ]]; then
        DO_DB=$(echo "$DATABASES" | sed -n "${DB_SELECTION}p")
      else
        DO_DB=$DB_SELECTION
      fi
    fi
  fi
fi

echo -e "${GREEN}Base de datos remota seleccionada: $DO_DB${NC}"

# Mostrar bases de datos disponibles localmente
echo -e "${YELLOW}Conectando a MySQL local para listar bases de datos disponibles...${NC}"
LOCAL_DATABASES=$(mysql -h $LOCAL_HOST -u $LOCAL_USER -p$LOCAL_PASS -e "SHOW DATABASES;" 2>/dev/null | grep -Ev "(Database|information_schema|performance_schema|mysql|sys)")

if [ $? -ne 0 ]; then
  echo -e "${RED}Error al conectar con MySQL local. Verifica tus credenciales.${NC}"
  exit 1
fi

echo -e "${GREEN}Bases de datos disponibles localmente:${NC}"
echo "$LOCAL_DATABASES" | nl

# Seleccionar base de datos local
if [ -z "$LOCAL_DB" ]; then
  read -p "Introduce el número o nombre de la base de datos local: " LOCAL_DB_SELECTION
  
  # Comprobar si es un número
  if [[ "$LOCAL_DB_SELECTION" =~ ^[0-9]+$ ]]; then
    LOCAL_DB=$(echo "$LOCAL_DATABASES" | sed -n "${LOCAL_DB_SELECTION}p")
  else
    LOCAL_DB=$LOCAL_DB_SELECTION
  fi
else
  echo -e "${YELLOW}Base de datos local actual: ${GREEN}$LOCAL_DB${NC}"
  # Si los nombres de las bases de datos son iguales y solo hay una base de datos local, no preguntar
  if [ "$DO_DB" = "$LOCAL_DB" ] && [ $(echo "$LOCAL_DATABASES" | wc -l) -eq 1 ]; then
    echo -e "${GREEN}Usando la misma base de datos para origen y destino${NC}"
  else
    read -p "¿Deseas cambiar la base de datos local? (s/N): " CHANGE_LOCAL_DB
    if [[ "$CHANGE_LOCAL_DB" =~ ^[Ss]$ ]]; then
      read -p "Introduce el número o nombre de la base de datos local: " LOCAL_DB_SELECTION
      
      # Comprobar si es un número
      if [[ "$LOCAL_DB_SELECTION" =~ ^[0-9]+$ ]]; then
        LOCAL_DB=$(echo "$LOCAL_DATABASES" | sed -n "${LOCAL_DB_SELECTION}p")
      else
        LOCAL_DB=$LOCAL_DB_SELECTION
      fi
    fi
  fi
fi

echo -e "${GREEN}Base de datos local seleccionada: $LOCAL_DB${NC}"

# Preguntar si se quiere sincronizar todas las tablas o solo algunas
read -p "¿Deseas sincronizar todas las tablas? (S/n): " SYNC_ALL_TABLES

if [[ "$SYNC_ALL_TABLES" =~ ^[Nn]$ ]]; then
  # Mostrar tablas disponibles
  echo -e "${YELLOW}Obteniendo lista de tablas de $DO_DB...${NC}"
  TABLES=$(mysql -h $DO_HOST -P $DO_PORT -u $DO_USER -p$DO_PASS --ssl-mode=REQUIRED -e "USE $DO_DB; SHOW TABLES;" 2>/dev/null | grep -v "Tables_in")
  
  echo -e "${GREEN}Tablas disponibles en $DO_DB:${NC}"
  echo "$TABLES" | nl
  
  read -p "Introduce los números de las tablas a sincronizar (separados por espacios): " TABLE_NUMBERS
  
  SELECTED_TABLES=""
  for NUM in $TABLE_NUMBERS; do
    TABLE=$(echo "$TABLES" | sed -n "${NUM}p")
    SELECTED_TABLES="$SELECTED_TABLES $TABLE"
  done
  
  echo -e "${GREEN}Tablas seleccionadas: $SELECTED_TABLES${NC}"
  
  # Confirmar antes de sincronizar
  read -p "¿Confirmas la sincronización de estas tablas? (s/N): " CONFIRM
  if [[ "$CONFIRM" =~ ^[Ss]$ ]]; then
    echo -e "${YELLOW}Sincronizando tablas específicas...${NC}"
    mysqldump -h $DO_HOST -P $DO_PORT -u $DO_USER -p$DO_PASS --ssl-mode=REQUIRED --set-gtid-purged=OFF $DO_DB $SELECTED_TABLES > /tmp/tables_backup.sql
    mysql -h $LOCAL_HOST -u $LOCAL_USER -p$LOCAL_PASS $LOCAL_DB < /tmp/tables_backup.sql
    echo -e "${GREEN}Sincronización de tablas completada: $(date)${NC}"
    show_elapsed_time
  else
    echo -e "${RED}Sincronización cancelada.${NC}"
    exit 0
  fi
else
  # Confirmar antes de sincronizar toda la base de datos
  read -p "¿Confirmas la sincronización completa de $DO_DB a $LOCAL_DB? (s/N): " CONFIRM
  if [[ "$CONFIRM" =~ ^[Ss]$ ]]; then
    echo -e "${YELLOW}Sincronizando base de datos completa...${NC}"
    mysqldump -h $DO_HOST -P $DO_PORT -u $DO_USER -p$DO_PASS --ssl-mode=REQUIRED --set-gtid-purged=OFF $DO_DB > /tmp/do_backup.sql
    mysql -h $LOCAL_HOST -u $LOCAL_USER -p$LOCAL_PASS $LOCAL_DB < /tmp/do_backup.sql
    echo -e "${GREEN}Sincronización completada: $(date)${NC}"
    show_elapsed_time
  else
    echo -e "${RED}Sincronización cancelada.${NC}"
    exit 0
  fi
fi 
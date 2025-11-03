#!/bin/bash

# Función para realizar la sincronización
sync_databases() {
  echo "Iniciando sincronización desde Digital Ocean a MySQL local..."
  
  # Exportar datos de Digital Ocean
  mysqldump -h $DO_DB_HOST -u $DO_DB_USER -p$DO_DB_PASSWORD $DO_DB_NAME > /tmp/do_backup.sql
  
  # Importar a la base de datos local
  mysql -h $LOCAL_DB_HOST -u $LOCAL_DB_USER -p$LOCAL_DB_PASSWORD $LOCAL_DB_NAME < /tmp/do_backup.sql
  
  echo "Sincronización completada: $(date)"
}

# Esperar a que MySQL esté disponible
echo "Esperando a que MySQL esté disponible..."
until mysqladmin ping -h $LOCAL_DB_HOST -u $LOCAL_DB_USER -p$LOCAL_DB_PASSWORD --silent; do
  sleep 5
done

echo "MySQL está disponible. Configurando sincronización periódica..."

# Realizar sincronización inicial
sync_databases

# Configurar sincronización periódica
while true; do
  sleep $SYNC_INTERVAL
  sync_databases
done 
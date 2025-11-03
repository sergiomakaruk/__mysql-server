#!/bin/bash

# Auto-Sync Script - Sincronización automática de bases de datos
# Lee configuración desde sync-config.yml y sincroniza sin preguntas

set -e

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables de entorno
CONFIG_FILE="/app/sync-config.yml"
LOG_DIR="/app/logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/sync_${TIMESTAMP}.log"

# Crear directorio de logs si no existe
mkdir -p "${LOG_DIR}"

# Función para logging
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Función para mensajes con color
print_msg() {
    local color=$1
    local msg=$2
    echo -e "${color}${msg}${NC}"
    log "INFO" "${msg}"
}

# Función para parsear YAML simple
parse_yaml() {
    local prefix=$2
    local s='[[:space:]]*'
    local w='[a-zA-Z0-9_]*'
    local fs=$(echo @|tr @ '\034')

    sed -ne "s|^\($s\):|\1|" \
         -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
         -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p" $1 |
    awk -F$fs '{
        indent = length($1)/2;
        vname[indent] = $2;
        for (i in vname) {if (i > indent) {delete vname[i]}}
        if (length($3) > 0) {
            vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
            printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
        }
    }'
}

# Función para obtener lista de bases de datos del config
get_databases_from_config() {
    grep -A 100 "^databases:" "${CONFIG_FILE}" | grep "^  - name:" | sed 's/.*name: *//' | tr -d '"' | tr -d "'"
}

# Función para obtener modo de una base de datos
get_db_mode() {
    local db_name=$1
    local in_db=false
    local mode="full"

    while IFS= read -r line; do
        if echo "$line" | grep -q "- name: *${db_name}"; then
            in_db=true
        elif echo "$line" | grep -q "- name:" && [ "$in_db" = true ]; then
            break
        elif [ "$in_db" = true ] && echo "$line" | grep -q "mode:"; then
            mode=$(echo "$line" | sed 's/.*mode: *//' | sed 's/#.*//' | sed 's/[[:space:]]*$//' | tr -d '"' | tr -d "'")
            break
        fi
    done < "${CONFIG_FILE}"

    echo "$mode"
}

# Función para obtener tablas a excluir
get_exclude_tables() {
    local db_name=$1
    local in_db=false
    local in_exclude=false
    local tables=()

    while IFS= read -r line; do
        if echo "$line" | grep -q "- name: *${db_name}"; then
            in_db=true
        elif echo "$line" | grep -q "^  - name:" && [ "$in_db" = true ]; then
            break
        elif [ "$in_db" = true ] && echo "$line" | grep -q "exclude_tables:"; then
            in_exclude=true
        elif [ "$in_exclude" = true ] && echo "$line" | grep -q "^      - "; then
            table=$(echo "$line" | sed 's/.*- *//' | sed 's/#.*//' | sed 's/[[:space:]]*$//' | tr -d '"' | tr -d "'")
            tables+=("$table")
        elif [ "$in_exclude" = true ] && echo "$line" | grep -q "^    [a-z]"; then
            break
        fi
    done < "${CONFIG_FILE}"

    echo "${tables[@]}"
}

# Función para verificar configuración de auto-sync
is_auto_sync_enabled() {
    grep -A 5 "^auto_sync:" "${CONFIG_FILE}" | grep "enabled:" | grep -q "true"
    return $?
}

# Función para sincronizar una base de datos
sync_database() {
    local db_name=$1
    local db_mode=$2
    local exclude_tables=("${@:3}")

    print_msg "${BLUE}" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_msg "${GREEN}" "📦 Sincronizando base de datos: ${db_name}"
    print_msg "${BLUE}" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Variables de conexión
    DO_HOST="${DO_HOST:-db-mysql-nyc1-49115-do-user-3306851-0.b.db.ondigitalocean.com}"
    DO_PORT="${DO_PORT:-25060}"
    DO_USER="${DO_USER:-doadmin}"
    DO_PASS="${DO_PASS}"

    LOCAL_HOST="mysql"
    LOCAL_USER="root"
    LOCAL_PASS="password"

    # Archivo temporal para el dump
    DUMP_FILE="/tmp/auto_sync_${db_name}_${TIMESTAMP}.sql"

    # Iniciar timer
    START_TIME=$(date +%s)

    # Verificar conexión a producción
    print_msg "${YELLOW}" "🔍 Verificando conexión a producción..."
    if ! mysql -h "${DO_HOST}" -P "${DO_PORT}" -u "${DO_USER}" -p"${DO_PASS}" \
              --ssl-mode=REQUIRED -e "USE ${db_name};" 2>/dev/null; then
        print_msg "${RED}" "❌ Error: No se puede conectar a la base de datos '${db_name}' en producción"
        return 1
    fi
    print_msg "${GREEN}" "✓ Conexión a producción exitosa"

    # Verificar conexión local
    print_msg "${YELLOW}" "🔍 Verificando conexión local..."
    if ! mysql -h "${LOCAL_HOST}" -u "${LOCAL_USER}" -p"${LOCAL_PASS}" -e "SHOW DATABASES;" &>/dev/null; then
        print_msg "${RED}" "❌ Error: No se puede conectar a MySQL local"
        return 1
    fi
    print_msg "${GREEN}" "✓ Conexión local exitosa"

    # Crear base de datos local si no existe
    print_msg "${YELLOW}" "🔨 Creando base de datos local si no existe..."
    mysql -h "${LOCAL_HOST}" -u "${LOCAL_USER}" -p"${LOCAL_PASS}" \
          -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\`;" 2>/dev/null

    # Construir comando mysqldump
    DUMP_CMD="mysqldump -h ${DO_HOST} -P ${DO_PORT} -u ${DO_USER} -p${DO_PASS} \
              --ssl-mode=REQUIRED \
              --set-gtid-purged=OFF \
              --single-transaction \
              --quick \
              --lock-tables=false"

    # Agregar exclusiones si es necesario
    if [ "$db_mode" = "exclude" ] && [ ${#exclude_tables[@]} -gt 0 ]; then
        print_msg "${YELLOW}" "⚠️  Modo exclusión activado. Tablas a excluir: ${exclude_tables[*]}"
        for table in "${exclude_tables[@]}"; do
            DUMP_CMD="${DUMP_CMD} --ignore-table=${db_name}.${table}"
        done
    else
        print_msg "${GREEN}" "✓ Modo completo: sincronizando todas las tablas"
    fi

    DUMP_CMD="${DUMP_CMD} ${db_name} > ${DUMP_FILE}"

    # Exportar desde producción
    print_msg "${YELLOW}" "📥 Exportando desde producción..."
    log "INFO" "Ejecutando: mysqldump de ${db_name}"

    if eval "${DUMP_CMD}" 2>>"${LOG_FILE}"; then
        DUMP_SIZE=$(du -h "${DUMP_FILE}" | cut -f1)
        print_msg "${GREEN}" "✓ Exportación completada (Tamaño: ${DUMP_SIZE})"
    else
        print_msg "${RED}" "❌ Error al exportar la base de datos"
        return 1
    fi

    # Importar a local
    print_msg "${YELLOW}" "📤 Importando a MySQL local..."
    log "INFO" "Importando ${db_name} a local"

    if mysql -h "${LOCAL_HOST}" -u "${LOCAL_USER}" -p"${LOCAL_PASS}" \
             --force "${db_name}" < "${DUMP_FILE}" 2>>"${LOG_FILE}"; then
        print_msg "${GREEN}" "✓ Importación completada"
    else
        print_msg "${RED}" "❌ Error al importar la base de datos"
        return 1
    fi

    # Limpiar archivo temporal
    rm -f "${DUMP_FILE}"

    # Calcular tiempo transcurrido
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    ELAPSED_MIN=$((ELAPSED / 60))
    ELAPSED_SEC=$((ELAPSED % 60))

    print_msg "${GREEN}" "✅ Base de datos '${db_name}' sincronizada exitosamente"
    print_msg "${BLUE}" "⏱️  Tiempo: ${ELAPSED_MIN}m ${ELAPSED_SEC}s"

    return 0
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

main() {
    print_msg "${BLUE}" "╔════════════════════════════════════════════════════════════╗"
    print_msg "${BLUE}" "║       🚀 SINCRONIZACIÓN AUTOMÁTICA DE BASES DE DATOS       ║"
    print_msg "${BLUE}" "╚════════════════════════════════════════════════════════════╝"
    echo ""

    log "INFO" "Iniciando sincronización automática"

    # Verificar que existe el archivo de configuración
    if [ ! -f "${CONFIG_FILE}" ]; then
        print_msg "${RED}" "❌ Error: No se encuentra el archivo de configuración: ${CONFIG_FILE}"
        log "ERROR" "Archivo de configuración no encontrado"
        exit 1
    fi

    print_msg "${GREEN}" "✓ Archivo de configuración encontrado"

    # Obtener lista de bases de datos
    DB_LIST=$(get_databases_from_config)

    if [ -z "$DB_LIST" ]; then
        print_msg "${RED}" "❌ Error: No se encontraron bases de datos en la configuración"
        log "ERROR" "No hay bases de datos configuradas"
        exit 1
    fi

    # Contar bases de datos
    DB_COUNT=$(echo "$DB_LIST" | wc -l)
    print_msg "${GREEN}" "✓ Bases de datos a sincronizar: ${DB_COUNT}"
    echo ""

    # Variables para tracking
    TOTAL_START=$(date +%s)
    SUCCESS_COUNT=0
    FAIL_COUNT=0

    # Iterar sobre cada base de datos
    DB_INDEX=1
    while IFS= read -r db_name; do
        [ -z "$db_name" ] && continue

        print_msg "${BLUE}" "📊 Progreso: Base de datos ${DB_INDEX}/${DB_COUNT}"
        echo ""

        # Obtener configuración de la BD
        DB_MODE=$(get_db_mode "$db_name")
        EXCLUDE_TABLES=($(get_exclude_tables "$db_name"))

        # Sincronizar
        if sync_database "$db_name" "$DB_MODE" "${EXCLUDE_TABLES[@]}"; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi

        echo ""
        DB_INDEX=$((DB_INDEX + 1))
    done <<< "$DB_LIST"

    # Resumen final
    TOTAL_END=$(date +%s)
    TOTAL_ELAPSED=$((TOTAL_END - TOTAL_START))
    TOTAL_MIN=$((TOTAL_ELAPSED / 60))
    TOTAL_SEC=$((TOTAL_ELAPSED % 60))

    print_msg "${BLUE}" "╔════════════════════════════════════════════════════════════╗"
    print_msg "${BLUE}" "║                    📊 RESUMEN FINAL                        ║"
    print_msg "${BLUE}" "╚════════════════════════════════════════════════════════════╝"
    print_msg "${GREEN}" "✅ Sincronizadas exitosamente: ${SUCCESS_COUNT}"
    if [ $FAIL_COUNT -gt 0 ]; then
        print_msg "${RED}" "❌ Fallidas: ${FAIL_COUNT}"
    fi
    print_msg "${BLUE}" "⏱️  Tiempo total: ${TOTAL_MIN}m ${TOTAL_SEC}s"
    print_msg "${BLUE}" "📝 Log guardado en: ${LOG_FILE}"

    log "INFO" "Sincronización completada. Exitosas: ${SUCCESS_COUNT}, Fallidas: ${FAIL_COUNT}"

    # Retornar código apropiado
    if [ $FAIL_COUNT -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Ejecutar script principal
main

.PHONY: sync-db sync-table backup-local sync-interactive

# Sincronizar toda la base de datos
sync-db:
	@echo "Sincronizando base de datos completa..."
	@docker-compose run --rm --entrypoint="/bin/bash" sync-command /scripts/sync-on-demand.sh
	@echo "Sincronización completada!"

# Sincronizar una tabla específica
sync-table:
	@echo "Sincronizando tabla $(TABLE)..."
	@docker-compose run --rm --entrypoint="/bin/bash" sync-command /scripts/sync-specific-tables.sh $(TABLE)
	@echo "Sincronización de tabla $(TABLE) completada!"

# Sincronización interactiva
sync-interactive:
	@echo "Iniciando sincronización interactiva..."
	@docker-compose run --rm sync-command /scripts/interactive-sync.sh
	@echo "Proceso de sincronización interactiva finalizado!"

# Hacer backup de la base de datos local antes de sincronizar
backup-local:
	@echo "Creando backup local..."
	@docker exec shared-mysql mysqldump -u root -ppassword laravel > ./backups/local_backup_$(shell date +%Y%m%d_%H%M%S).sql
	@echo "Backup completado!" 
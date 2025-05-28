#!/bin/bash

# Konfigurasi
DB_CONTAINER="odoo-db-1"        # Ganti sesuai nama container PostgreSQL-mu
DB_NAME="odoo"                # Nama database
DB_USER="odoo"                # Username PostgreSQL
BACKUP_NAME="backup_$(date +%Y%m%d_%H%M%S).sql"

echo "📦 Membackup database '$DB_NAME' dari container '$DB_CONTAINER'..."
docker exec -t $DB_CONTAINER pg_dump -U $DB_USER $DB_NAME > $BACKUP_NAME

echo "✅ Backup selesai: $BACKUP_NAME"


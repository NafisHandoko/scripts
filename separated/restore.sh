#!/bin/bash

# Konfigurasi
DB_CONTAINER="odoo-db-1"        # Ganti sesuai nama container PostgreSQL-mu
DB_USER="odoo"                # Username PostgreSQL
RESTORE_DB="odoo_restore"     # Nama database tujuan restore
BACKUP_FILE=$1                # Nama file backup sebagai argumen

if [ -z "$BACKUP_FILE" ]; then
  echo "❗ Gunakan: ./restore.sh nama_file_backup.sql"
  exit 1
fi

echo "🔄 Merestore file '$BACKUP_FILE' ke database '$RESTORE_DB'..."
docker exec -i $DB_CONTAINER psql -U $DB_USER -c "DROP DATABASE IF EXISTS $RESTORE_DB;"
docker exec -i $DB_CONTAINER psql -U $DB_USER -c "CREATE DATABASE $RESTORE_DB OWNER $DB_USER;"
cat $BACKUP_FILE | docker exec -i $DB_CONTAINER psql -U $DB_USER -d $RESTORE_DB

echo "✅ Restore selesai."


#!/bin/bash

# Konfigurasi nama container dan database
DB_CONTAINER="odoo-db-1"
DB_USER="odoo"
OLD_DB_NAME="odoo"
RESTORED_DB_NAME="odoo_restore"
ODOO_CONTAINER="odoo-web-1"

echo "🚨 Pastikan data di '$OLD_DB_NAME' sudah dibackup sebelum melanjutkan."
read -p "Lanjutkan menghapus database '$OLD_DB_NAME' dan menggantinya dengan '$RESTORED_DB_NAME'? (y/n): " confirm

if [[ "$confirm" != "y" ]]; then
  echo "❌ Operasi dibatalkan."
  exit 1
fi

echo "🗑️ Menghapus database lama: $OLD_DB_NAME..."
docker exec -i $DB_CONTAINER psql -U $DB_USER -c "DROP DATABASE IF EXISTS $OLD_DB_NAME;"

echo "🔁 Merename database $RESTORED_DB_NAME menjadi $OLD_DB_NAME..."
docker exec -i $DB_CONTAINER psql -U $DB_USER -c "ALTER DATABASE $RESTORED_DB_NAME RENAME TO $OLD_DB_NAME;"

echo "♻️ Restart container Odoo..."
docker restart $ODOO_CONTAINER

echo "✅ Database '$OLD_DB_NAME' kini berisi data dari '$RESTORED_DB_NAME'."


#!/bin/bash

# Nama container Odoo
ODOO_CONTAINER="odoo-web-1"
# Lokasi file konfigurasi Odoo di dalam container
ODOO_CONF_PATH="/etc/odoo/odoo.conf"

# Mode yang dipilih: enable / disable
MODE="$1"

if [[ "$MODE" != "enable" && "$MODE" != "disable" ]]; then
  echo "❌ Usage: $0 <enable|disable>"
  echo "Contoh: ./toggle_odoo_dbaccess.sh enable"
  exit 1
fi

echo "🔧 Mengubah konfigurasi Odoo di container: $ODOO_CONTAINER"

if [[ "$MODE" == "enable" ]]; then
  echo "✅ Mengaktifkan akses ke semua database (list_db = True, dbfilter = .*)"
  docker exec "$ODOO_CONTAINER" sed -i \
    -e 's/^list_db *=.*/list_db = True/' \
    -e 's/^dbfilter *=.*/dbfilter = .*/' \
    "$ODOO_CONF_PATH"

elif [[ "$MODE" == "disable" ]]; then
  echo "🚫 Menonaktifkan akses ke semua database selain 'odoo'"
  docker exec "$ODOO_CONTAINER" sed -i \
    -e 's/^list_db *=.*/list_db = False/' \
    -e 's/^dbfilter *=.*/dbfilter = ^odoo$/' \
    "$ODOO_CONF_PATH"
fi

echo "🔄 Restarting container $ODOO_CONTAINER..."
docker restart "$ODOO_CONTAINER"

echo "✅ Selesai."


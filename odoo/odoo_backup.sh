#!/bin/bash

# Konfigurasi global
DB_CONTAINER="odoo-db-1"
ODOO_CONTAINER="odoo-web-1"
DB_NAME="odoo"
DB_RESTORE="odoo_restore"
BACKUP_DIR="./backups"

mkdir -p "$BACKUP_DIR"

function backup() {
  DATE=$(date +"%Y-%m-%d")
  read -p "📝 Masukkan catatan/deskripsi backup (tanpa spasi): " NOTE
  NOTE=${NOTE// /_}  # Replace spaces with underscores
  
  if [ -z "$NOTE" ]; then
    NOTE="no_note"
  fi

  echo "📦 Membackup database '$DB_NAME'..."
  docker exec -t $DB_CONTAINER pg_dump -U odoo $DB_NAME > "$BACKUP_DIR/db_${DB_NAME}_${DATE}_${NOTE}.dump"

  echo "🗂 Membackup filestore..."
  docker cp $ODOO_CONTAINER:/var/lib/odoo/filestore/$DB_NAME "$BACKUP_DIR/filestore_${DB_NAME}_${DATE}_${NOTE}"
  tar -czf "$BACKUP_DIR/filestore_${DB_NAME}_${DATE}_${NOTE}.tar.gz" -C "$BACKUP_DIR" "filestore_${DB_NAME}_${DATE}_${NOTE}"
  rm -rf "$BACKUP_DIR/filestore_${DB_NAME}_${DATE}_${NOTE}"

  echo "✅ Backup selesai: $BACKUP_DIR/db_${DB_NAME}_${DATE}_${NOTE}.dump + filestore"
}

function restore() {
  echo "🗓 Backup yang tersedia:"
  ls "$BACKUP_DIR" | grep -E 'db_.*\.dump' | sort
  read -p "Masukkan tanggal backup yang ingin direstore (format: YYYY-MM-DD): " DATE
  read -p "Masukkan catatan backup (kosongkan jika backup lama tanpa catatan): " NOTE
  NOTE=${NOTE// /_}  # Replace spaces with underscores

  # Try both filename formats
  DB_FILE_WITH_NOTE="$BACKUP_DIR/db_${DB_NAME}_${DATE}_${NOTE}.dump"
  DB_FILE_WITHOUT_NOTE="$BACKUP_DIR/db_${DB_NAME}_${DATE}.dump"
  FILESTORE_FILE_WITH_NOTE="$BACKUP_DIR/filestore_${DB_NAME}_${DATE}_${NOTE}.tar.gz"
  FILESTORE_FILE_WITHOUT_NOTE="$BACKUP_DIR/filestore_${DB_NAME}_${DATE}.tar.gz"

  # Determine which files to use
  if [ -z "$NOTE" ]; then
    # If no note provided, try the old format first
    if [ -f "$DB_FILE_WITHOUT_NOTE" ]; then
      DB_FILE="$DB_FILE_WITHOUT_NOTE"
      FILESTORE_FILE="$FILESTORE_FILE_WITHOUT_NOTE"
    else
      echo "❌ Backup dengan tanggal tersebut tidak ditemukan!"
      return
    fi
  else
    # If note provided, try the new format
    if [ -f "$DB_FILE_WITH_NOTE" ]; then
      DB_FILE="$DB_FILE_WITH_NOTE"
      FILESTORE_FILE="$FILESTORE_FILE_WITH_NOTE"
    else
      echo "❌ Backup dengan tanggal dan catatan tersebut tidak ditemukan!"
      return
    fi
  fi

  if [[ ! -f "$DB_FILE" || ! -f "$FILESTORE_FILE" ]]; then
    echo "❌ File backup tidak lengkap (database atau filestore tidak ditemukan)!"
    return
  fi

  echo "🧱 Membuat database $DB_RESTORE..."
  docker exec -i $DB_CONTAINER psql -U odoo -c "DROP DATABASE IF EXISTS $DB_RESTORE;"
  docker exec -i $DB_CONTAINER psql -U odoo -c "CREATE DATABASE $DB_RESTORE OWNER odoo;"

  echo "📂 Merestore database..."
  docker exec -i $DB_CONTAINER psql -U odoo $DB_RESTORE < "$DB_FILE" > /dev/null 2>&1

  echo "📂 Merestore filestore..."
  if [ -z "$NOTE" ]; then
    tar -xzf "$FILESTORE_FILE" -C "$BACKUP_DIR"
    docker cp "$BACKUP_DIR/filestore_${DB_NAME}_${DATE}" "$ODOO_CONTAINER:/var/lib/odoo/filestore/$DB_RESTORE"
    docker exec -iu root $ODOO_CONTAINER chown -R odoo:odoo "/var/lib/odoo/filestore/$DB_RESTORE"
    rm -rf "$BACKUP_DIR/filestore_${DB_NAME}_${DATE}"
  else
    tar -xzf "$FILESTORE_FILE" -C "$BACKUP_DIR"
    docker cp "$BACKUP_DIR/filestore_${DB_NAME}_${DATE}_${NOTE}" "$ODOO_CONTAINER:/var/lib/odoo/filestore/$DB_RESTORE"
    docker exec -iu root $ODOO_CONTAINER chown -R odoo:odoo "/var/lib/odoo/filestore/$DB_RESTORE"
    rm -rf "$BACKUP_DIR/filestore_${DB_NAME}_${DATE}_${NOTE}"
  fi

  echo "✅ Restore selesai. Akses di: http://localhost:8069/web/login?db=$DB_RESTORE"
}

function apply_restore() {
  echo "⚠️  PERINGATAN! Ini akan menggantikan database '$DB_NAME' dengan isi dari '$DB_RESTORE'"
  read -p "Lanjutkan? (yes/no): " CONFIRM

  if [[ "$CONFIRM" != "yes" ]]; then
    echo "❌ Dibatalkan."
    return
  fi

  echo "🛑 Menghentikan container Odoo (web)..."
  docker stop $ODOO_CONTAINER

  echo "💥 Menghapus database lama '$DB_NAME'..."
  docker exec -i $DB_CONTAINER psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;"

  echo "🧱 Membuat database baru '$DB_NAME'..."
  docker exec -i $DB_CONTAINER psql -U odoo -d postgres -c "CREATE DATABASE $DB_NAME OWNER odoo;"

  echo "📋 Menyalin isi dari '$DB_RESTORE' ke '$DB_NAME'..."
  docker exec -i $DB_CONTAINER pg_dump -U odoo $DB_RESTORE | docker exec -i $DB_CONTAINER psql -U odoo $DB_NAME > /dev/null 2>&1

  echo "Menghapus database '$DB_RESTORE'..."
  docker exec -t $DB_CONTAINER psql -U odoo -c "DROP DATABASE $DB_RESTORE;"

  echo "🚀 Menyalakan kembali container Odoo..."
  docker start $ODOO_CONTAINER
  sleep 5

  echo "🗂 Menyalin filestore..."
  docker exec -i $ODOO_CONTAINER rm -rf /var/lib/odoo/filestore/$DB_NAME
  docker exec -i $ODOO_CONTAINER cp -r /var/lib/odoo/filestore/$DB_RESTORE /var/lib/odoo/filestore/$DB_NAME
  docker exec -iu root $ODOO_CONTAINER chown -R odoo:odoo /var/lib/odoo/filestore/$DB_NAME

  echo "✅ Apply restore selesai. Akses Odoo seperti biasa di: http://localhost:8069"
}

function list_backups() {
  echo "📁 Daftar file backup di folder $BACKUP_DIR:"
  ls -lh "$BACKUP_DIR" | grep -E 'db_.*\.dump|filestore_.*\.tar\.gz' | sort
}

function delete_old_backups() {
  echo "🗑 Hapus backup lama"
  echo "Backup yang tersedia:"
  ls "$BACKUP_DIR" | grep -E 'db_.*\.dump' | sort
  read -p "Masukkan tanggal backup yang ingin dihapus (format: YYYY-MM-DD): " DATE
  read -p "Masukkan catatan backup (kosongkan jika backup lama tanpa catatan): " NOTE
  NOTE=${NOTE// /_}  # Replace spaces with underscores

  # Try both filename formats
  DB_FILE_WITH_NOTE="$BACKUP_DIR/db_${DB_NAME}_${DATE}_${NOTE}.dump"
  DB_FILE_WITHOUT_NOTE="$BACKUP_DIR/db_${DB_NAME}_${DATE}.dump"
  FILESTORE_FILE_WITH_NOTE="$BACKUP_DIR/filestore_${DB_NAME}_${DATE}_${NOTE}.tar.gz"
  FILESTORE_FILE_WITHOUT_NOTE="$BACKUP_DIR/filestore_${DB_NAME}_${DATE}.tar.gz"

  # Determine which files to use
  if [ -z "$NOTE" ]; then
    # If no note provided, try the old format
    if [ -f "$DB_FILE_WITHOUT_NOTE" ]; then
      DB_FILE="$DB_FILE_WITHOUT_NOTE"
      FILESTORE_FILE="$FILESTORE_FILE_WITHOUT_NOTE"
    else
      echo "❌ Backup dengan tanggal tersebut tidak ditemukan!"
      return
    fi
  else
    # If note provided, try the new format
    if [ -f "$DB_FILE_WITH_NOTE" ]; then
      DB_FILE="$DB_FILE_WITH_NOTE"
      FILESTORE_FILE="$FILESTORE_FILE_WITH_NOTE"
    else
      echo "❌ Backup dengan tanggal dan catatan tersebut tidak ditemukan!"
      return
    fi
  fi

  if [[ -f "$DB_FILE" ]]; then
    rm "$DB_FILE"
    echo "✔️ Hapus $DB_FILE"
  else
    echo "❌ File database tidak ditemukan"
  fi

  if [[ -f "$FILESTORE_FILE" ]]; then
    rm "$FILESTORE_FILE"
    echo "✔️ Hapus $FILESTORE_FILE"
  else
    echo "❌ File filestore tidak ditemukan"
  fi
}

while true; do
  echo ""
  echo "===== 📦 Odoo Backup & Restore Menu ====="
  echo "1. Backup database + filestore"
  echo "2. Restore dari backup ke odoo_restore"
  echo "3. Apply restore: odoo_restore ➜ odoo"
  echo "4. Lihat daftar backup"
  echo "5. Hapus backup berdasarkan tanggal"
  echo "0. Keluar"
  echo "========================================="
  read -p "Pilih menu [0-5]: " CHOICE

  case $CHOICE in
    1) backup ;;
    2) restore ;;
    3) apply_restore ;;
    4) list_backups ;;
    5) delete_old_backups ;;
    0) echo "👋 Bye!"; break ;;
    *) echo "❌ Pilihan tidak valid";;
  esac
done


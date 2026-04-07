#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/source-env.sh"

if [ -z "${DB_BACKUP_USER:-}" ] || [ -z "${DB_BACKUP_PASSWORD:-}" ]; then
    echo "Errore: DB_BACKUP_USER e DB_BACKUP_PASSWORD devono essere definiti in .env" >&2
    exit 1
fi

BACKUP_DIR="${BACKUP_DB_DIR:-/home/ubuntu/backup-db}"
DATE=$(date +"%Y-%m-%d")
RCLONE_DEST="${RCLONE_REMOTE_DB:-gdrive:backup-mia-vps/db}"

# Crea la cartella di backup se non esiste
mkdir -p "$BACKUP_DIR"

# Recupera i database
echo "Recupero dei database..."
DBS=$(mysql -u "$DB_BACKUP_USER" -p"$DB_BACKUP_PASSWORD" -e 'SHOW DATABASES;' 2>/dev/null | grep -Ev "(Database|information_schema|performance_schema|mysql)")

if [ $? -ne 0 ]; then
    echo "Errore nel recupero dei database. Controlla le credenziali di accesso."
    exit 1
fi

# Esegui il backup di ogni database
for DB in $DBS; do
    echo "Eseguendo il backup del database: $DB..."
    mysqldump -u "$DB_BACKUP_USER" -p"$DB_BACKUP_PASSWORD" "$DB" | gzip > "$BACKUP_DIR/${DATE}_$DB.sql.gz"

    if [ $? -eq 0 ]; then
        echo "Backup di $DB completato con successo."
    else
        echo "Errore durante il backup di $DB."
    fi
done

# Copia i backup su Google Drive
echo "Copia dei backup su Google Drive..."
rclone copy "$BACKUP_DIR" "$RCLONE_DEST"

if [ $? -eq 0 ]; then
    echo "Backup copiato su Google Drive con successo."
else
    echo "Errore durante la copia su Google Drive."
    exit 1
fi

echo "Backup completato."

#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$SCRIPT_DIR/.env"
    set +a
fi

# Funzione per eliminare file e cartelle più vecchi di 90 giorni
cleanup_local() {
    local dir=$1
    echo "Inizio la pulizia in $dir..."

    # Controllo se la directory esiste
    if [ -d "$dir" ]; then
        find "$dir" -type f -mtime +90 -exec rm -f {} \; && echo "File più vecchi di 90 giorni eliminati in $dir."
        find "$dir" -type d -mtime +90 -exec rm -rf {} \; && echo "Cartelle più vecchie di 90 giorni eliminate in $dir."
    else
        echo "Errore: la directory $dir non esiste."
    fi
}

# Funzione per eliminare file e cartelle più vecchi di 90 giorni su Google Drive
cleanup_remote() {
    local remote_dir=$1
    echo "Inizio la pulizia in $remote_dir..."

    # Esegui il comando rclone e controlla l'uscita
    if rclone delete --min-age 90d "$remote_dir"; then
        echo "File più vecchi di 90 giorni eliminati in $remote_dir."
    else
        echo "Errore durante la pulizia in $remote_dir."
    fi
}

DEFAULT_LOCAL="/home/ubuntu/backup /home/ubuntu/backup-db"
DEFAULT_REMOTE="gdrive:backup-mia-vps/files gdrive:backup-mia-vps/db"

read -r -a local_dirs <<< "${RETENTION_LOCAL_DIRS:-$DEFAULT_LOCAL}"
read -r -a remote_dirs <<< "${RETENTION_REMOTE_DIRS:-$DEFAULT_REMOTE}"

# Esegui la pulizia locale
for dir in "${local_dirs[@]}"; do
    cleanup_local "$dir"
done

# Esegui la pulizia remota
for dir in "${remote_dirs[@]}"; do
    cleanup_remote "$dir"
done

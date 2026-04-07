#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/source-env.sh"

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    echo "Errore: TELEGRAM_BOT_TOKEN e TELEGRAM_CHAT_ID devono essere definiti in .env" >&2
    exit 1
fi

SOURCE_DIR="${SOURCE_WEB_DIR:-/var/www/html}"
CURRENT_DATE=$(date +"%Y-%m-%d")
BACKUP_DIR="${BACKUP_FILES_ROOT:-/home/ubuntu/backup}/$CURRENT_DATE"
ERROR_LOG="${ERROR_LOG_BACKUP_FILES:-/home/ubuntu/errors_backup_files.log}"
RCLONE_DEST="${RCLONE_REMOTE_FILES:-gdrive:backup-mia-vps/files}"
# Nome del remote rclone (es. gdrive da "gdrive:cartella/...")
RCLONE_REMOTE_NAME="${RCLONE_DEST%%:*}"

echo "Verifica connessione rclone (${RCLONE_REMOTE_NAME})..."
if ! rclone_about_err=$(rclone about "${RCLONE_REMOTE_NAME}:" 2>&1); then
    echo "$rclone_about_err" >&2
    echo "" >&2
    echo "rclone non riesce ad autenticarsi (di solito: token OAuth scaduto o revocato)." >&2
    echo "Sul server esegui:" >&2
    echo "  rclone config reconnect ${RCLONE_REMOTE_NAME}:" >&2
    echo "Completa il browser OAuth, poi rilancia questo script." >&2
    exit 1
fi

# Prima del backup: su Drive, solo in questo percorso, controlla ed elimina file più vecchi di N giorni
RETENTION_DAYS="${BACKUP_FILES_REMOTE_RETENTION_DAYS:-90}"
MIN_AGE="${RETENTION_DAYS}d"
echo "Drive (${RCLONE_DEST}): controllo file più vecchi di ${RETENTION_DAYS} giorni..."
if ! old_remote_list=$(rclone lsf "${RCLONE_DEST}" -R --files-only --min-age "$MIN_AGE" 2>&1); then
    echo "Errore nell'elenco remoto (rclone lsf): ${old_remote_list}" >&2
    echo "$(date): rclone lsf fallito per ${RCLONE_DEST}" >> "$ERROR_LOG"
    exit 1
fi
if echo "$old_remote_list" | grep -q .; then
    echo "Trovati file oltre i ${RETENTION_DAYS} giorni, rimozione in corso..."
    if ! rclone delete --min-age "$MIN_AGE" "${RCLONE_DEST}"; then
        echo "Errore durante la pulizia remota (rclone delete)." >&2
        echo "$(date): rclone delete --min-age fallito per ${RCLONE_DEST}" >> "$ERROR_LOG"
        exit 1
    fi
    echo "Pulizia remota completata."
else
    echo "Nessun file oltre i ${RETENTION_DAYS} giorni da rimuovere su Drive."
fi

# Funzione per inviare messaggi su Telegram
send_telegram_message() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=$message" \
        -d "parse_mode=Markdown"
}

# Crea la directory di backup locale se non esiste
mkdir -p "$BACKUP_DIR"

# Crea la directory remota su Google Drive se non esiste
if ! rclone mkdir "${RCLONE_DEST}/"; then
    echo "Errore durante la creazione della directory remota su Google Drive" >> "$ERROR_LOG"
fi

# Variabili per il resoconto del backup
successful_backups=()
successful_uploads=()
failed_backups=()
failed_uploads=()

# Loop attraverso ogni sottocartella in SOURCE_DIR
for dir in "$SOURCE_DIR"/*/; do
    # Estrae il nome della cartella
    dirname=$(basename "$dir")

    echo "Inizio del backup per la cartella: $dirname"

    # Crea il file di backup tar.gz con la data nel nome
    if tar --exclude='access.log' --exclude='error.log' -czpf "$BACKUP_DIR/${CURRENT_DATE}_${dirname}.tar.gz" -C "$SOURCE_DIR" "$dirname"; then
        echo "Backup creato con successo: ${CURRENT_DATE}_${dirname}.tar.gz"
        successful_backups+=("$dirname")

        # Copia il file di backup su Google Drive senza la cartella data
        if rclone copy "$BACKUP_DIR/${CURRENT_DATE}_${dirname}.tar.gz" "$RCLONE_DEST/"; then
            echo "Caricamento su Google Drive completato per: ${CURRENT_DATE}_${dirname}.tar.gz"
            successful_uploads+=("$dirname")
        else
            echo "Errore durante il caricamento di ${CURRENT_DATE}_${dirname}.tar.gz su Google Drive" >> "$ERROR_LOG"
            failed_uploads+=("$dirname")
        fi
    else
        echo "Errore durante la creazione del backup per $dirname" >> "$ERROR_LOG"
        failed_backups+=("$dirname")
    fi

    echo "Fine del backup per la cartella: $dirname"
    echo "-----------------------------------"
done

# Crea il resoconto del backup
backup_report="*Resoconto del backup per $CURRENT_DATE:*\n\n"

if [ ${#successful_backups[@]} -gt 0 ]; then
    backup_report+="Backup creati con successo:\n"
    backup_report+="$(printf '• %s\n' "${successful_backups[@]}")\n"
fi

if [ ${#successful_uploads[@]} -gt 0 ]; then
    backup_report+="Caricamento su Google Drive completato per:\n"
    backup_report+="$(printf '• %s\n' "${successful_uploads[@]}")\n"
fi

if [ ${#failed_backups[@]} -gt 0 ]; then
    backup_report+="Backup non completati:\n"
    backup_report+="$(printf '• %s\n' "${failed_backups[@]}")\n"
fi

if [ ${#failed_uploads[@]} -gt 0 ]; then
    backup_report+="Caricamento su Google Drive fallito per:\n"
    backup_report+="$(printf '• %s\n' "${failed_uploads[@]}")\n"
fi

# Invia il resoconto del backup su Telegram
send_telegram_message "${backup_report//\\n/%0A}"

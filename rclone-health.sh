#!/bin/bash
# Verifica che i remote rclone configurati rispondano; in caso di errore invia Telegram.
# Cron tipico come root: la config rclone è /root/.config/rclone/rclone.conf
# (rclone config reconnect va eseguito da root, come i backup).
#
# Esempio cron (1 volta al giorno alle 8:00): il file di log riceve solo output in caso
# di errore; se tutto OK non scrive nulla (né log né spam). Da terminale interattivo
# stampa una riga di OK. Forzare messaggio: RCLONE_HEALTH_VERBOSE=1 ./rclone-health.sh
#   0 8 * * * /data/scripts/rclone-health.sh >> /var/log/rclone-health.log 2>&1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/source-env.sh"

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    echo "Errore: TELEGRAM_BOT_TOKEN e TELEGRAM_CHAT_ID devono essere definiti in .env" >&2
    exit 1
fi

send_telegram_plain() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${message}"
}

# Raccoglie nomi remote unici (es. gdrive) da RCLONE_REMOTE_DB e RCLONE_REMOTE_FILES
paths_raw="${RCLONE_REMOTE_DB:-} ${RCLONE_REMOTE_FILES:-}"
unique_remotes=()
for path in $paths_raw; do
    [ -z "$path" ] && continue
    r="${path%%:*}"
    [ -z "$r" ] && continue
    dup=0
    for existing in "${unique_remotes[@]}"; do
        if [ "$existing" = "$r" ]; then
            dup=1
            break
        fi
    done
    [ "$dup" -eq 0 ] && unique_remotes+=("$r")
done

if [ ${#unique_remotes[@]} -eq 0 ]; then
    echo "Nessun remote rclone da controllare (imposta RCLONE_REMOTE_* in .env)." >&2
    exit 1
fi

failed_remotes=()
failed_msgs=()

for remote in "${unique_remotes[@]}"; do
    if ! err=$(rclone about "${remote}:" 2>&1); then
        failed_remotes+=("$remote")
        if [ "${#err}" -gt 1200 ]; then
            err="${err:0:1200}…"
        fi
        failed_msgs+=("$err")
    fi
done

if [ ${#failed_remotes[@]} -eq 0 ]; then
    if [ -t 1 ] || [ "${RCLONE_HEALTH_VERBOSE:-}" = 1 ]; then
        ts_ok=$(date "+%Y-%m-%d %H:%M:%S")
        echo "${ts_ok} rclone OK: ${unique_remotes[*]}"
    fi
    exit 0
fi

ts=$(date "+%Y-%m-%d %H:%M:%S")
host="$(hostname 2>/dev/null || echo "server")"
msg="rclone: verifica FALLITA su ${host}"$'\n'"(${ts})"$'\n\n'

# Stesso dettaglio su Telegram e nel file di log (cron: >> log 2>&1)
echo "${ts} rclone FALLITO su ${host} — remote: ${failed_remotes[*]}" >&2
for i in "${!failed_remotes[@]}"; do
    msg+="Remote: ${failed_remotes[$i]}"$'\n'
    msg+="${failed_msgs[$i]}"$'\n\n'
    echo "--- rclone about ${failed_remotes[$i]}: ---" >&2
    echo "${failed_msgs[$i]}" >&2
done

msg+="Rinnova il token sul server (come root, stesso utente di cron):"$'\n'
for r in "${failed_remotes[@]}"; do
    msg+="rclone config reconnect ${r}:"$'\n'
done

send_telegram_plain "$msg"
echo "${ts} rclone: notifica Telegram inviata (errore sopra)." >&2
exit 1

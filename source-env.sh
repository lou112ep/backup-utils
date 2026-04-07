#!/usr/bin/env bash
# Carica le variabili da .env nella cartella cron.
# Uso: SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" && source "$SCRIPT_DIR/source-env.sh"

: "${SCRIPT_DIR:?}"

ENV_FILE="${CRON_ENV_FILE:-$SCRIPT_DIR/.env}"
if [ ! -f "$ENV_FILE" ]; then
    echo "Errore: file di configurazione non trovato: $ENV_FILE" >&2
    echo "Copia cron/.env.example in cron/.env e inserisci le credenziali." >&2
    exit 1
fi

set -a
# shellcheck disable=SC1091
. "$ENV_FILE"
set +a

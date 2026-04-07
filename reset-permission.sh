#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$SCRIPT_DIR/.env"
    set +a
fi

WEB_ROOT="${WEB_ROOT:-/var/www}"

# Imposta il proprietario e il gruppo
chown -R www-data:www-data "$WEB_ROOT"

# Imposta i permessi per i file a 644
find "$WEB_ROOT" -type f -exec chmod 644 {} \;

# Imposta i permessi per le directory a 755
find "$WEB_ROOT" -type d -exec chmod 755 {} \;

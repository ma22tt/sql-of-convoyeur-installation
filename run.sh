#!/bin/bash
# version sqlite
#   ./run.sh          reconstruit la base et lance les requetes
#   ./run.sh reset    reconstruit la base seulement
#   ./run.sh shell    ouvre une invite pour taper tes requetes

set -euo pipefail
cd "$(dirname "$0")"

DOSSIER=sqlite
DB=$DOSSIER/entrepot.db

reconstruire() {
    rm -f "$DB"
    sqlite3 "$DB" < $DOSSIER/01_schema.sql
    sqlite3 "$DB" < $DOSSIER/02_donnees.sql
}

case "${1:-tout}" in
    reset)
        reconstruire
        echo "base reconstruite : $DB"
        ;;
    shell)
        reconstruire
        echo ".tables pour la liste, .quit pour sortir."
        echo ""
        sqlite3 -box -header "$DB"
        ;;
    tout)
        reconstruire
        echo ""
        sqlite3 "$DB" < $DOSSIER/03_requetes.sql
        ;;
    *)
        echo "usage: ./run.sh [reset|shell]" >&2
        exit 1
        ;;
esac

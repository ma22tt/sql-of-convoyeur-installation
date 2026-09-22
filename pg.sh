#!/bin/bash
# pilote le serveur postgres
#   ./pg.sh up        demarre
#   ./pg.sh requetes  recharge les donnees et lance les requetes
#   ./pg.sh shell     ouvre psql
#   ./pg.sh etat      dit si ca tourne
#   ./pg.sh logs      journaux en direct
#   ./pg.sh reset     recharge schema + donnees
#   ./pg.sh down      arrete, garde les donnees
#   ./pg.sh detruire  arrete et efface tout

set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f .env ]; then
    echo "il manque le fichier .env. copie .env.example et mets un mot de passe." >&2
    exit 1
fi

# shellcheck disable=SC1091
set -a; . ./.env; set +a

CONTENEUR=entrepot-db
psql_() { docker exec -i "$CONTENEUR" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" "$@"; }

attendre() {
    printf "attente du serveur"
    for _ in $(seq 1 30); do
        if docker exec "$CONTENEUR" pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; then
            echo " : pret."
            return 0
        fi
        printf "."
        sleep 1
    done
    echo " : delai depasse." >&2
    return 1
}

case "${1:-etat}" in
    up)
        docker compose up -d
        attendre
        echo "le serveur tourne, visible dans docker desktop."
        echo "joignable depuis ta machine seulement, sur localhost:5432."
        ;;
    requetes)
        # on recharge d'abord, sinon la transaction du bloc 9 fausse le passage suivant
        psql_ -q -f - < postgres/01_schema.sql  > /dev/null 2>&1
        psql_ -q -f - < postgres/02_donnees.sql > /dev/null 2>&1
        psql_ -f - < postgres/03_requetes.sql
        ;;
    shell)
        echo "\\dt pour les tables, \\q pour sortir."
        docker exec -it "$CONTENEUR" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
        ;;
    etat)    docker compose ps ;;
    logs)    docker compose logs -f db ;;
    reset)
        psql_ -f - < postgres/01_schema.sql
        psql_ -f - < postgres/02_donnees.sql
        echo "recharge."
        ;;
    down)
        docker compose down
        echo "arrete. les donnees restent dans le volume."
        ;;
    detruire)
        docker compose down -v
        echo "arrete, volume efface."
        ;;
    *)
        echo "usage: ./pg.sh [up|requetes|shell|etat|logs|reset|down|detruire]" >&2
        exit 1
        ;;
esac

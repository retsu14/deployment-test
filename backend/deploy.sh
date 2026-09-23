#!/usr/bin/env bash
# Build and (re)start the backend stack. Safe to run again and again.
set -euo pipefail

cd "$(dirname "$0")"

COMPOSE="docker compose --env-file .env.production -f docker-compose.prod.yml"

if [ ! -f .env.production ]; then
	echo "ERROR: .env.production is missing."
	echo "Run:  cp .env.production.example .env.production  &&  nano .env.production"
	exit 1
fi

echo "==> Building images (first run takes a few minutes)"
$COMPOSE build

echo "==> Starting containers"
$COMPOSE up -d --remove-orphans

echo "==> Cleaning up old images"
docker image prune -f >/dev/null

echo "==> Done. Current status:"
$COMPOSE ps

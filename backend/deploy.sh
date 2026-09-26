#!/usr/bin/env bash
# Build and (re)start the backend stack. Safe to run again and again.
set -euo pipefail

cd "$(dirname "$0")"

COMPOSE="docker compose --env-file .env.production -f docker-compose.prod.yaml"

if [ ! -f .env.production ]; then
	echo "ERROR: .env.production is missing."
	echo "Run:  cp .env.production.example .env.production  &&  nano .env.production"
	exit 1
fi

# Laravel needs an encryption key. Generate one the first time and keep it in
# .env.production -- the same key has to be used on every later deploy, or
# sessions and encrypted data become unreadable.
if ! grep -q '^APP_KEY=base64:' .env.production; then
	echo "==> No APP_KEY in .env.production -- generating one"
	KEY="base64:$(openssl rand -base64 32 | tr -d '\n')"
	if grep -q '^APP_KEY=' .env.production; then
		sed -i "s|^APP_KEY=.*|APP_KEY=${KEY}|" .env.production
	else
		printf 'APP_KEY=%s\n' "$KEY" >> .env.production
	fi
fi

echo "==> Building images (first run takes a few minutes)"
$COMPOSE build

echo "==> Starting containers"
$COMPOSE up -d --remove-orphans

echo "==> Cleaning up old images"
docker image prune -f >/dev/null

echo "==> Done. Current status:"
$COMPOSE ps

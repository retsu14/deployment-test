#!/bin/sh
set -e

cd /var/www/html
# Ensure Git writes its global config to a writable location (the working directory) and mark the directory as safe
export HOME=/var/www/html
git config --global --add safe.directory /var/www/html

# --- Development only: bind-mounted volume may be missing dependencies -------
if [ "$APP_ENV" != "production" ]; then
    if [ ! -f vendor/autoload.php ]; then
        echo "[entrypoint] Installing composer dependencies..."
        composer install --no-interaction --prefer-dist
    fi

    # Generate an app key into the (bind-mounted) .env if it has none.
    if [ -f .env ] && ! grep -q '^APP_KEY=base64:' .env; then
        echo "[entrypoint] Generating APP_KEY..."
        php artisan key:generate --force || true
    fi

    if [ -f .env ] && grep -q '^APP_KEY=base64:' .env; then
        APP_KEY="$(grep '^APP_KEY=' .env | tail -n 1 | cut -d= -f2-)"
        export APP_KEY
    fi
fi

# --- Storage skeleton -------------------------------------------------------
# In production storage/ is a named Docker volume, which starts out empty on a
# brand new server. Recreate the folders Laravel expects before booting.
mkdir -p storage/app/public \
         storage/framework/cache/data \
         storage/framework/sessions \
         storage/framework/views \
         storage/logs

# --- Production sanity check ------------------------------------------------
if [ "$APP_ENV" = "production" ] && [ -z "$APP_KEY" ]; then
    echo "[entrypoint] ERROR: APP_KEY is not set."
    echo "[entrypoint] Generate one with: php artisan key:generate --show"
    echo "[entrypoint] then put it in .env.production and deploy again."
    exit 1
fi

# --- Wait for the database --------------------------------------------------
# On the very first boot MySQL reports "healthy" a moment before it really
# accepts connections on port 3306, so retry for up to two minutes.
echo "[entrypoint] Waiting for the database..."
attempt=0
until php -r 'exit(@fsockopen(getenv("DB_HOST") ?: "db", (int) (getenv("DB_PORT") ?: 3306), $e, $s, 2) ? 0 : 1);' 2>/dev/null; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 60 ]; then
        echo "[entrypoint] ERROR: the database never became reachable."
        exit 1
    fi
    sleep 2
done

# --- Database migrations ----------------------------------------------------
echo "[entrypoint] Running migrations..."
if [ "$APP_ENV" = "production" ]; then
    # Fail loudly: a silently broken app is harder to debug than a stopped one.
    php artisan migrate --force || {
        echo "[entrypoint] ERROR: migrations failed. Check the database settings"
        echo "[entrypoint] in .env.production, then deploy again."
        exit 1
    }
else
    php artisan migrate --force || true
fi

# --- Optimize for production / keep fresh for dev ---------------------------
if [ "$APP_ENV" = "production" ]; then
    echo "[entrypoint] Caching config, routes and views..."
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
else
    php artisan optimize:clear || true
fi

if [ ! -e public/storage ]; then
    php artisan storage:link || true
fi

echo "[entrypoint] Starting: $*"
exec "$@"

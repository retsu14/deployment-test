# Fullstack Template

Laravel (API) + Next.js (frontend) + MySQL, all in Docker.

- `backend/` -- Laravel 12 on PHP 8.4, served by nginx + PHP-FPM
- `frontend/` -- Next.js 16 (React 19, Tailwind 4)

## Running it locally

The two halves each have their own compose file for development. Start the
backend first, because the frontend joins its network:

```bash
cd backend
cp .env.example .env
docker compose up -d
```

Then the frontend:

```bash
cd ../frontend
cp .env.example .env
docker compose up -d
```

| What                | Where                                          |
| ------------------- | ---------------------------------------------- |
| Frontend            | http://localhost:3000                          |
| API                 | http://localhost:3001                          |
| phpMyAdmin          | http://localhost:3002                          |

Both run with hot reload -- edit a file and the browser updates.

## Putting it on a server

See **[DEPLOY.md](DEPLOY.md)**. Production uses a single stack at the repo
root (`docker-compose.prod.yml`) that runs all five services together behind
Caddy, which handles HTTPS automatically.

```bash
cp .env.production.example .env.production   # fill it in
./deploy.sh
```

The development compose files are *not* used in production: production images
bake the code and dependencies in, publish no database ports, and serve real
builds instead of dev servers.

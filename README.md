# Fullstack Template

Laravel (API) + Next.js (frontend) + MySQL, all in Docker for local work.

- `backend/` -- Laravel 12 on PHP 8.4, served by nginx + PHP-FPM
- `frontend/` -- Next.js 16 (React 19, Tailwind 4)

The two halves are deployed to **different places**: the backend to a VPS, the
frontend to Cloudflare Pages.

## Running it locally

Start the backend first, because the frontend joins its Docker network:

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

| What       | Where                 |
| ---------- | --------------------- |
| Frontend   | http://localhost:3000 |
| API        | http://localhost:3001 |
| phpMyAdmin | http://localhost:3002 |

Both run with hot reload -- edit a file and the browser updates.

## Deploying

**Backend -> VPS.** See **[backend/DEPLOY.md](backend/DEPLOY.md)**. Production
runs a separate stack (`backend/docker-compose.prod.yml`) with five services
behind Caddy, which handles HTTPS automatically and serves two subdomains:
`api.yoursite.com` for Laravel and `db.yoursite.com` for phpMyAdmin (behind a
password prompt). MySQL has no open port at all.

```bash
cd backend
cp .env.production.example .env.production
./deploy.sh
```

The development compose files are *not* used in production: production images
bake the code and dependencies in, publish no database ports, and serve a real
build instead of a dev server.

**Frontend -> Cloudflare Pages.** Connect the repo, set the build directory to
`frontend`, and add the environment variable `NEXT_PUBLIC_API_URL` pointing at
your API domain.

The two sides must agree on each other's addresses:

| Set this              | Where                            | To                         |
| --------------------- | -------------------------------- | -------------------------- |
| `NEXT_PUBLIC_API_URL` | Cloudflare Pages                 | `https://api.yoursite.com` |
| `FRONTEND_URL`        | `backend/.env.production` on VPS | your Cloudflare address    |

`FRONTEND_URL` is what allows the browser to make cross-site calls to the API
(CORS). If it doesn't exactly match, every request from the frontend fails.

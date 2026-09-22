# Deploying to a VPS

This guide takes a fresh Ubuntu server and puts your app online with HTTPS.
Budget about 30 minutes the first time.

**What you end up with:**

```
                 the internet
                      |
                 [ Caddy ]  <- port 80/443, handles HTTPS for free
                  /      \
    yoursite.com /        \ api.yoursite.com
                /          \
        [ frontend ]     [ web (nginx) ]
         Next.js              |
                          [ app ] Laravel / PHP
                              |
                          [ db ] MySQL
```

Only Caddy is reachable from the internet. The database has no open port at
all -- the only way in is through the app.

---

## What you need first

1. A **VPS** running Ubuntu 22.04 or 24.04 (Hostinger, DigitalOcean, Vultr,
   Contabo -- any of them, the cheapest plan is fine).
2. A **domain name**, pointed at your server.
3. The server's **IP address** and root password (your VPS provider emails these).

> **No domain yet?** You can still practice. Use a free wildcard DNS name based
> on your IP: if your server is `203.0.113.10`, then
> `app.203.0.113.10.nip.io` and `api.203.0.113.10.nip.io` already point at it,
> no signup needed, and HTTPS still works. Use those as your two domains.

---

## Step 1 -- Point your domain at the server

In your domain registrar's DNS settings, add two **A records**:

| Type | Name  | Value (your server IP) |
| ---- | ----- | ---------------------- |
| A    | `@`   | `203.0.113.10`         |
| A    | `api` | `203.0.113.10`         |

The first is your site, the second is your API. DNS can take a few minutes to
spread. Check it worked:

```bash
ping yoursite.com
```

If it replies with your server's IP, you are good. **Do this before Step 5** --
HTTPS certificates only work once DNS points at the server.

---

## Step 2 -- Log in to the server

From your own computer:

```bash
ssh root@203.0.113.10
```

Everything from here runs **on the server**.

---

## Step 3 -- Install Docker

One command, straight from Docker:

```bash
curl -fsSL https://get.docker.com | sh
```

Check it worked:

```bash
docker --version && docker compose version
```

---

## Step 4 -- Get your code onto the server

```bash
git clone https://github.com/your-username/your-repo.git app
cd app
```

> Private repo? Either use a GitHub Personal Access Token when it asks for a
> password, or set up a deploy key. A public repo needs neither.

---

## Step 5 -- Fill in your settings

```bash
cp .env.production.example .env.production
nano .env.production
```

Change these:

| Setting                                | Set it to                                     |
| -------------------------------------- | --------------------------------------------- |
| `APP_DOMAIN`                           | `yoursite.com`                                |
| `API_DOMAIN`                           | `api.yoursite.com`                            |
| `ACME_EMAIL`                           | your real email (Let's Encrypt expiry notices)|
| `NEXT_PUBLIC_API_URL`                  | `https://api.yoursite.com`                    |
| `APP_URL`                              | `https://api.yoursite.com`                    |
| `DB_PASSWORD` / `DB_ROOT_PASSWORD`     | long random passwords                         |

Save with `Ctrl+O`, `Enter`, then exit with `Ctrl+X`.

Now generate the app key (Laravel needs it to encrypt sessions and cookies):

```bash
docker compose -f docker-compose.prod.yml run --rm app php artisan key:generate --show
```

Copy the whole `base64:....` line it prints, then put it in the file:

```bash
nano .env.production      # paste it after APP_KEY=
```

---

## Step 6 -- Deploy

```bash
./deploy.sh
```

The first run builds everything and takes 3-10 minutes. When it finishes you
should see all five containers `Up`, with `app`, `db` and `web` marked
`healthy`.

Open **https://yoursite.com** in a browser. You should see your app, with a
padlock. Caddy fetched a real HTTPS certificate on its own.

---

## Step 7 -- Lock the server down (recommended)

```bash
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw enable
```

Only SSH and web traffic can reach the server now.

---

## Shipping an update

Every time you change your code:

```bash
cd app
git pull
./deploy.sh
```

That rebuilds what changed, restarts the containers, and runs any new database
migrations automatically. Your database and uploaded files are kept in Docker
volumes, so they survive every deploy.

---

## Everyday commands

Run these from the project folder on the server.

```bash
# See what's running
docker compose --env-file .env.production -f docker-compose.prod.yml ps

# Watch the logs live (Ctrl+C to stop)
docker compose --env-file .env.production -f docker-compose.prod.yml logs -f

# Logs for one service only
docker compose --env-file .env.production -f docker-compose.prod.yml logs -f app

# Run an artisan command
docker compose --env-file .env.production -f docker-compose.prod.yml exec app php artisan about

# Open a shell inside the Laravel container
docker compose --env-file .env.production -f docker-compose.prod.yml exec app sh

# Stop everything (data is kept)
docker compose --env-file .env.production -f docker-compose.prod.yml down
```

That prefix is long, so make a shortcut once:

```bash
echo "alias dc='docker compose --env-file .env.production -f docker-compose.prod.yml'" >> ~/.bashrc
source ~/.bashrc
```

Then it's just `dc ps`, `dc logs -f`, `dc exec app sh`.

### Backing up the database

```bash
dc exec db sh -c 'mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' > backup.sql
```

Copy `backup.sql` off the server. Do this before anything risky.

---

## When something goes wrong

**The site doesn't load at all**
Check the containers are up: `dc ps`. If one keeps restarting, read its logs:
`dc logs app`.

**"Your connection is not private" / no padlock**
Caddy could not get a certificate. Almost always DNS: the domain must point at
this server *before* Caddy starts. Fix the DNS, wait, then `dc restart caddy`.
See what it's complaining about with `dc logs caddy`.

**`app` container keeps restarting**
Read `dc logs app`. The two usual messages are `APP_KEY is not set` (redo the
key step) and `migrations failed` (check the `DB_` values in
`.env.production`).

**The frontend loads but can't reach the API**
`NEXT_PUBLIC_API_URL` is baked in when the image is *built*, not when it runs.
If you change it, you must rebuild: `./deploy.sh` does that for you.

**Port 80 is already in use**
Something else (often Apache) is on it: `systemctl disable --now apache2`.

**Out of disk space**
Old images pile up: `docker system prune -a`.

---

## Things to add later

This setup deliberately stays small. When the app grows you'll want:

- A **queue worker** (`php artisan queue:work`) as a sixth service, since
  `QUEUE_CONNECTION=database` currently has nothing processing jobs.
- The **scheduler** (`php artisan schedule:work`) if you use scheduled tasks.
- **Redis** for cache and sessions instead of the database.
- **Automated backups** of the `mysql-data` volume to somewhere off the server.
- A **deploy user** instead of `root`, and SSH keys instead of passwords.

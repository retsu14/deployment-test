# Deploying the backend to a VPS

This guide takes a fresh Ubuntu server and puts the Laravel API online with
HTTPS. Budget about 30 minutes the first time.

The **frontend is not deployed here** -- it goes on Cloudflare Pages. The two
halves live on different servers and talk over the internet:

```
   [ Cloudflare Pages ]                    [ your VPS ]
      Next.js frontend  ---- https --->   [ Caddy ] port 80/443
    yoursite.pages.dev                        |      (free HTTPS)
                                          [ web ] nginx
                                              |
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
2. A **domain name**, so the API can have HTTPS.
3. The server's **IP address** and root password (your VPS provider emails these).

> **No domain yet?** You can still practice. Use a free wildcard DNS name based
> on your IP: if your server is `203.0.113.10`, then `api.203.0.113.10.nip.io`
> already points at it, no signup needed, and HTTPS still works.

---

## Step 1 -- Point your subdomains at the server

Every address you want to open in a browser needs its own **A record**. Add
two, both pointing at the same server:

| Type | Name  | Value (your server IP) | Gives you            |
| ---- | ----- | ---------------------- | -------------------- |
| A    | `api` | `203.0.113.10`         | `api.yoursite.com`   |
| A    | `db`  | `203.0.113.10`         | `db.yoursite.com`    |

The first is the Laravel API. The second is phpMyAdmin, so you can look at the
database from a browser.

**The database itself never gets a DNS record.** MySQL is not a website -- it
has no port open to the internet at all. Nothing outside the server can dial
it directly. The only ways to the data are through the API, or through
phpMyAdmin, and both live inside the same private Docker network:

```
      api.yoursite.com ---> [ Caddy ] ---> nginx -> Laravel --+
                                |                             |
      db.yoursite.com  ---> [ Caddy ] ---> phpMyAdmin --------+--> [ db ]
                          (asks for a                              no open
                           password first)                          port
```

Check the records work:

```bash
ping api.yoursite.com
```

If it replies with your server's IP, you are good. **Do this before Step 6** --
HTTPS certificates only work once DNS points at the server.

> **Using Cloudflare for your DNS?** Set both records to **DNS only** (click
> the orange cloud so it turns grey). If they stay orange, Cloudflare hides
> your server and Caddy cannot prove it owns the domain. You can switch them
> back on later, but only after setting SSL mode to **Full (strict)**.

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
cd app/backend
```

Note the `backend` at the end -- everything below runs in that folder.

> Private repo? Either use a GitHub Personal Access Token when it asks for a
> password, or set up a deploy key. A public repo needs neither.

---

## Step 5 -- Fill in your settings

```bash
cp .env.production.example .env.production
nano .env.production
```

Change these:

| Setting                            | Set it to                                                  |
| ---------------------------------- | ---------------------------------------------------------- |
| `API_DOMAIN`                       | `api.yoursite.com`                                         |
| `DB_DOMAIN`                        | `db.yoursite.com`                                          |
| `ACME_EMAIL`                       | your real email (Let's Encrypt expiry notices)             |
| `FRONTEND_URL`                     | your Cloudflare address, e.g. `https://yoursite.pages.dev` |
| `APP_URL`                          | `https://api.yoursite.com`                                 |
| `DB_PASSWORD` / `DB_ROOT_PASSWORD` | long random passwords                                      |
| `DB_AUTH_USER` / `DB_AUTH_HASH`    | the phpMyAdmin door lock -- see Step 5b                    |

Save with `Ctrl+O`, `Enter`, then exit with `Ctrl+X`.

`FRONTEND_URL` matters more than it looks: browsers refuse to let your
frontend read answers from a different address unless the API names that
address. Get it wrong and every request fails with a CORS error.

---

## Step 5b -- Put a lock on phpMyAdmin

`db.yoursite.com` is open to the whole internet, and bots scan for phpMyAdmin
around the clock. So Caddy asks for a username and password *before* anything
reaches phpMyAdmin -- two locks instead of one.

Pick a password, then turn it into a hash:

```bash
docker run --rm caddy:2-alpine caddy hash-password --plaintext 'your-password-here'
```

It prints something like `$2a$14$jUXW2krGwHA...`. Put it in `.env.production`:

```
DB_AUTH_USER=admin
DB_AUTH_HASH='$2a$14$jUXW2krGwHA...'
```

> **Keep the single quotes.** The hash is full of `$` signs, and Docker reads
> `$` as the start of a variable name. Without quotes it silently chops the
> hash down to `$2a$14`, and then the password never works no matter what you
> type. This one catches everybody.

The password is stored only as a hash, so even someone reading this file
cannot see the original.

**Prefer not to expose it at all?** See
[Reaching phpMyAdmin without opening it to the internet](#reaching-phpmyadmin-without-opening-it-to-the-internet)
at the end -- the safest option needs no `db` DNS record.

---

Now generate the app key (Laravel needs it to encrypt sessions and cookies):

```bash
docker compose -f docker-compose.prod.yml run --rm app php artisan key:generate --show
```

Copy the whole `base64:....` line it prints, then put it in the file:

```bash
nano .env.production
```

Paste it after `APP_KEY=`.

---

## Step 6 -- Deploy

```bash
./deploy.sh
```

> Says `Permission denied`? The file lost its "runnable" flag on the way from
> Windows. Fix it once: `chmod +x deploy.sh`

The first run builds everything and takes 3-10 minutes. When it finishes you
should see five containers `Up`, with `app`, `db` and `web` marked `healthy`.

Test the API from your own computer:

```bash
curl https://api.yoursite.com/up
```

You should get a page saying **Application up**, over HTTPS, with a valid
certificate that Caddy fetched on its own.

Then open **https://db.yoursite.com** in a browser. You should get a small
browser password box first (that is Caddy, using `DB_AUTH_USER` /
`DB_AUTH_HASH`), and only after that the phpMyAdmin login. Log in there with
your `DB_USERNAME` and `DB_PASSWORD` -- the two logins are separate on
purpose.

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

## Step 8 -- Point the frontend at your API

Over on Cloudflare Pages, set the environment variable:

```
NEXT_PUBLIC_API_URL = https://api.yoursite.com
```

Then **redeploy the frontend**. `NEXT_PUBLIC_*` values are baked in when the
site is built, so changing the variable alone does nothing until it rebuilds.

If the frontend's address ever changes, update `FRONTEND_URL` in
`.env.production` on the VPS and run `./deploy.sh` again -- the two must match.

---

## Shipping an update

Every time you change backend code:

```bash
cd app/backend
git pull
./deploy.sh
```

That rebuilds what changed, restarts the containers, and runs any new database
migrations automatically. Your database and uploaded files are kept in Docker
volumes, so they survive every deploy.

The frontend deploys on its own whenever you push -- Cloudflare handles that.

---

## Everyday commands

Run these from the `backend` folder on the server.

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml ps
```

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml logs -f
```

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml logs -f app
```

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml exec app php artisan about
```

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml exec app sh
```

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml down
```

In order: see what is running, watch all logs live (`Ctrl+C` to stop), watch
one service's logs, run an artisan command, open a shell inside the Laravel
container, and stop everything (your data is kept).

That prefix is long, so make a shortcut once:

```bash
echo "alias dc='docker compose --env-file .env.production -f docker-compose.prod.yml'" >> ~/.bashrc
```

Reload it with `source ~/.bashrc`, and then it is just `dc ps`, `dc logs -f`,
`dc exec app sh`.

### Backing up the database

```bash
dc exec db sh -c 'mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' > backup.sql
```

Copy `backup.sql` off the server. Do this before anything risky.

---

## When something goes wrong

**The API doesn't respond at all**
Check the containers are up: `dc ps`. If one keeps restarting, read its logs:
`dc logs app`.

**"Your connection is not private" / no padlock**
Caddy could not get a certificate. Almost always DNS: the domain must point at
this server *before* Caddy starts, and the Cloudflare record must be grey
(DNS only). Fix it, then `dc restart caddy`. See `dc logs caddy`.

**The frontend gets "blocked by CORS policy" in the browser console**
`FRONTEND_URL` on the server does not exactly match the address the browser is
on. It must include `https://` and have no trailing slash. Fix it and run
`./deploy.sh` -- a restart alone is not enough, the config is cached.

**The frontend calls `localhost` instead of your API**
`NEXT_PUBLIC_API_URL` was missing when Cloudflare built the site. Set it and
redeploy the frontend.

**phpMyAdmin keeps asking for the password, even when it's right**
The hash got cut short. Check `.env.production` -- `DB_AUTH_HASH` must be
wrapped in single quotes and end with a long string of letters, not with
`$2a$14`. Redo Step 5b, then `./deploy.sh`.

**phpMyAdmin loads but says it can't connect to the server**
Check the database is healthy (`dc ps`). The `PMA_HOST` is the container name
`db`, not `localhost` -- localhost inside a container means the container
itself.

**`app` container keeps restarting**
Read `dc logs app`. The two usual messages are `APP_KEY is not set` (redo the
key step) and `migrations failed` (check the `DB_` values in
`.env.production`).

**Port 80 is already in use**
Something else (often Apache) is on it: `systemctl disable --now apache2`.

**Out of disk space**
Old images pile up: `docker system prune -a`.

---

## Reaching phpMyAdmin without opening it to the internet

Publishing phpMyAdmin at `db.yoursite.com` is convenient -- and convenient for
attackers too. The Caddy password stops the casual scanning, but a database
admin panel on the public internet is still the riskiest thing in this setup.

The safer option is an **SSH tunnel**: phpMyAdmin stays completely unreachable
from outside, and you borrow the server's own private network for as long as
you need it.

To do that, give the `phpmyadmin` service a localhost-only port in
`docker-compose.prod.yml`:

```yaml
    ports:
      - "127.0.0.1:8080:80"
```

`127.0.0.1:` is the important part -- it means "this server only", not the
internet. Then delete the `{$DB_DOMAIN}` block from the `Caddyfile`, and drop
the `db` DNS record.

Now, from your own computer:

```bash
ssh -L 8080:localhost:8080 root@203.0.113.10
```

Leave that terminal open and go to **http://localhost:8080** in your browser.
You are looking at phpMyAdmin on the server, through the SSH connection you
already trust. Close the terminal and the door closes with it.

Which to teach? Start with the Caddy version because students can see it work
in a browser immediately. Show the tunnel once they are comfortable -- it is
how this is usually done on a real production server.

---

## Things to add later

This setup deliberately stays small. When the app grows you will want:

- **API routes.** This template's routes live in `routes/web.php`. A real API
  usually puts them in `routes/api.php` (`php artisan install:api`), which also
  brings in Sanctum for token login.
- A **queue worker** (`php artisan queue:work`) as an extra service, since
  `QUEUE_CONNECTION=database` currently has nothing processing jobs.
- The **scheduler** (`php artisan schedule:work`) if you use scheduled tasks.
- **Redis** for cache and sessions instead of the database.
- **Automated backups** of the `mysql-data` volume to somewhere off the server.
- A **deploy user** instead of `root`, and SSH keys instead of passwords.

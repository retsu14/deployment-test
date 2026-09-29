# Deploying the backend to a VPS

This guide takes a fresh Ubuntu server and puts the Laravel API online with
HTTPS. Budget about 30 minutes the first time.

The **frontend is not deployed here** -- it goes on Cloudflare Pages. The two
halves live on different servers and talk over the internet:

```
   [ Cloudflare Pages ]                 [ your VPS ]
      Next.js frontend  --- https --->  nginx  (installed on the VPS,
    yoursite.pages.dev                    |      owns ports 80/443)
                                          |
                          127.0.0.1:8000  |  127.0.0.1:8001
                     +--------------------+--------------------+
                     |          Docker stack "api"             |
                     |   web (nginx) -> app (Laravel) -> db    |
                     |   phpmyadmin ---------------------> db  |
                     +-----------------------------------------+
```

There are **two nginx** here, and they do different jobs:

- **nginx on the VPS** is the front door. It takes requests for your domains,
  handles HTTPS, and passes them into Docker. You install it with `apt`.
- **nginx inside Docker** (the `web` container) serves Laravel. It comes with
  this project -- you never touch it.

The Docker stack only listens on `127.0.0.1`, which means "this server only".
Nothing on the internet can reach it except through the front door. The
database has no open port at all.

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

| Type | Name  | Value (your server IP) | Gives you          |
| ---- | ----- | ---------------------- | ------------------ |
| A    | `api` | `203.0.113.10`         | `api.yoursite.com` |
| A    | `db`  | `203.0.113.10`         | `db.yoursite.com`  |

The first is the Laravel API. The second is phpMyAdmin, so you can look at the
database from a browser.

**The database itself never gets a DNS record.** MySQL is not a website -- it
has no port open to the internet at all. The only ways to the data are through
the API, or through phpMyAdmin.

Check the records work:

```bash
ping api.yoursite.com
```

If it replies with your server's IP, you are good. **Do this before Step 9** --
HTTPS certificates only work once DNS points at the server.

> **Using Cloudflare for your DNS?** Set both records to **DNS only** (click
> the orange cloud so it turns grey). If they stay orange, Cloudflare hides
> your server and certbot cannot prove you own the domain. You can switch them
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

## Step 4 -- Install nginx and certbot

```bash
sudo apt update
```

```bash
sudo apt install -y nginx certbot python3-certbot-nginx apache2-utils
```

That is four things: **nginx** (the front door), **certbot** (gets free HTTPS
certificates from Let's Encrypt), its **nginx plugin** (so certbot can set up
HTTPS in nginx for you), and **apache2-utils** (only for the `htpasswd`
command that makes the phpMyAdmin password -- it does not install Apache).

Check nginx is running:

```bash
systemctl status nginx --no-pager
```

It should say `active (running)`. Opening `http://your-server-ip` in a browser
now shows "Welcome to nginx!".

---

## Step 5 -- Get your code onto the server

```bash
git clone https://github.com/your-username/your-repo.git app
cd app/backend
```

Note the `backend` at the end -- everything below runs in that folder.

> Private repo? Either use a GitHub Personal Access Token when it asks for a
> password, or set up a deploy key. A public repo needs neither.

---

## Step 6 -- Fill in your settings

```bash
cp .env.production.example .env.production
nano .env.production
```

Change these:

| Setting                            | Set it to                                                  |
| ---------------------------------- | ---------------------------------------------------------- |
| `DB_DOMAIN`                        | `db.yoursite.com`                                          |
| `FRONTEND_URL`                     | your Cloudflare address, e.g. `https://yoursite.pages.dev` |
| `APP_URL`                          | `https://api.yoursite.com`                                 |
| `DB_PASSWORD` / `DB_ROOT_PASSWORD` | long random passwords                                      |

Save with `Ctrl+O`, `Enter`, then exit with `Ctrl+X`.

`FRONTEND_URL` matters more than it looks: browsers refuse to let your
frontend read answers from a different address unless the API names that
address. Get it wrong and every request fails with a CORS error.

> **Decide the `DB_` values now.** MySQL reads them only once, the first time
> it creates its data. Changing them later does nothing -- see "Access denied"
> under [When something goes wrong](#when-something-goes-wrong).

### About `APP_KEY` -- leave it empty

Laravel needs a key to encrypt sessions and cookies, but you do not have to
make one. Leave `APP_KEY=` blank. `./deploy.sh` generates a key the first time
it runs, writes it into `.env.production`, and reuses that same key on every
later deploy. You will see this once:

```
==> No APP_KEY in .env.production -- generating one
```

---

## Step 7 -- Start the Docker stack

```bash
./deploy.sh
```

> Says `Permission denied`? The file lost its "runnable" flag on the way from
> Windows. Fix it once: `chmod +x deploy.sh`

The first run builds everything and takes 3-10 minutes. It builds the images,
starts the containers, then runs the database migrations. When it finishes you
should see `app`, `db` and `web` marked `healthy`.

Check the API answers **on the server itself** -- nginx is not pointing at it
yet, so this is the only place it works right now:

```bash
curl http://127.0.0.1:8000/up
```

You should get **Application up**. If you do not, stop here and look at
`docker compose --env-file .env.production -f docker-compose.prod.yaml logs app`
-- there is no point setting up nginx in front of a stack that is not running.

---

## Step 8 -- Put nginx in front of the stack

**The phpMyAdmin password.** `db.yoursite.com` is open to the whole internet,
and bots scan for phpMyAdmin around the clock. So nginx asks for a username and
password *before* anything reaches phpMyAdmin -- two locks instead of one.

```bash
sudo htpasswd -c /etc/nginx/.htpasswd admin
```

It asks you to type a password twice. The file only stores a hash of it.

**The site file.** This project ships a ready-made one:

```bash
sudo cp nginx-site.conf.example /etc/nginx/sites-available/api
```

```bash
sudo nano /etc/nginx/sites-available/api
```

Replace `api.yoursite.com` and `db.yoursite.com` with your real domains. Leave
the `127.0.0.1:8000` / `127.0.0.1:8001` lines alone -- they already match
`docker-compose.prod.yaml`.

Turn the site on, test the file, and load it:

```bash
sudo ln -s /etc/nginx/sites-available/api /etc/nginx/sites-enabled/
```

```bash
sudo nginx -t
```

```bash
sudo systemctl reload nginx
```

Always run `sudo nginx -t` before reloading. It checks the file and points at
the exact line if something is wrong, instead of taking your sites down.

Now `http://api.yoursite.com/up` works from your own computer -- over plain
http for the moment.

---

## Step 9 -- Turn on HTTPS

```bash
sudo certbot --nginx -d api.yoursite.com -d db.yoursite.com
```

It asks for your email (for expiry warnings) and to accept the terms. Then it
gets the certificates, adds HTTPS to your nginx site file, and redirects plain
http to https -- all by itself.

Test it from your own computer:

```bash
curl https://api.yoursite.com/up
```

You should get **Application up**, with a padlock. Then open
**https://db.yoursite.com** in a browser. You get a small browser password box
first (nginx, using the `htpasswd` password), and only after that the
phpMyAdmin login. Log in there with your `DB_USERNAME` and `DB_PASSWORD` -- the
two logins are separate on purpose.

Certificates last 90 days, and certbot renews them automatically. You can check
renewal works with:

```bash
sudo certbot renew --dry-run
```

---

## Step 10 -- Lock the server down (recommended)

```bash
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw enable
```

Only SSH and web traffic (80 and 443) can reach the server now.

> **ufw does not protect Docker ports.** Ports that Docker opens skip ufw
> completely. That is why `docker-compose.prod.yaml` binds everything to
> `127.0.0.1:` -- that, not ufw, is what keeps the stack off the internet.
> Never remove the `127.0.0.1:` part.

---

## Step 11 -- Point the frontend at your API

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
migrations. Your database and uploaded files are kept in Docker volumes, so
they survive every deploy. nginx and the certificates are not touched.

The frontend deploys on its own whenever you push -- Cloudflare handles that.

---

## Deploying another API on the same server

One VPS can run several APIs from this same codebase. The nginx on the VPS
stays the single front door; each API gets its own Docker stack, its own
database, and its own two ports.

**1. Clone into a new folder**

```bash
git clone https://github.com/your-username/your-repo.git app2
cd app2/backend
```

**2. Change 5 lines in `docker-compose.prod.yaml`**

| Line                    | API 1 (first one)      | API 2                  | API 3                  |
| ----------------------- | ---------------------- | ---------------------- | ---------------------- |
| `name:`                 | `api`                  | `api2`                 | `api3`                 |
| `web` -> `image:`       | `laravel-api-web:prod` | `api2-web:prod`        | `api3-web:prod`        |
| `app` -> `image:`       | `laravel-api-app:prod` | `api2-app:prod`        | `api3-app:prod`        |
| `web` -> `ports:`       | `127.0.0.1:8000:80`    | `127.0.0.1:8010:80`    | `127.0.0.1:8020:80`    |
| `phpmyadmin` -> `ports:`| `127.0.0.1:8001:80`    | `127.0.0.1:8011:80`    | `127.0.0.1:8021:80`    |

Why each one matters:

- **`name:`** -- Docker uses it to tell stacks apart. Two stacks with the same
  name are treated as *one*: the second deploy silently takes over the first
  API's containers **and its database**. The name is also put in front of the
  volumes and network (`api2_mysql-data`), which is why you do not have to
  rename those.
- **`image:`** -- with the same image name, the first API would run the second
  API's code the next time it restarts.
- **`ports:`** -- two programs cannot listen on the same port. The tens digit
  tells you which API it is: 800x is API 1, 801x is API 2, 802x is API 3.

Do not change `db`, the networks, or the volumes.

**3. Its own `.env.production`**

Its own `DB_DOMAIN`, `APP_URL`, `FRONTEND_URL` and `DB_` passwords. Leave
`APP_KEY=` empty -- `./deploy.sh` makes a new one for this API.

**4. Deploy it** -- `./deploy.sh`, then `curl http://127.0.0.1:8010/up`.

**5. Its own nginx site file**

```bash
sudo cp nginx-site.conf.example /etc/nginx/sites-available/api2
sudo nano /etc/nginx/sites-available/api2
```

This time change the domains **and** the two `proxy_pass` ports to `8010` and
`8011`. The phpMyAdmin password file can be shared by all APIs. Then:

```bash
sudo ln -s /etc/nginx/sites-available/api2 /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d api.site2.com -d db.site2.com
```

**6. DNS** -- two A records for the new domains, pointing at the same IP.

> Each API runs its own MySQL, PHP, nginx and phpMyAdmin, roughly 600 MB-1 GB
> of memory per API. Check what the server has with `free -h` before adding
> one.

---

## Everyday commands

Run the Docker ones from the `backend` folder on the server.

```bash
docker compose --env-file .env.production -f docker-compose.prod.yaml ps
```

```bash
docker compose --env-file .env.production -f docker-compose.prod.yaml logs -f
```

```bash
docker compose --env-file .env.production -f docker-compose.prod.yaml logs -f app
```

```bash
docker compose --env-file .env.production -f docker-compose.prod.yaml exec app php artisan about
```

```bash
docker compose --env-file .env.production -f docker-compose.prod.yaml exec app sh
```

```bash
docker compose --env-file .env.production -f docker-compose.prod.yaml down
```

In order: see what is running, watch all logs live (`Ctrl+C` to stop), watch
one service's logs, run an artisan command, open a shell inside the Laravel
container, and stop everything (your data is kept).

That prefix is long, so make a shortcut once:

```bash
echo "alias dc='docker compose --env-file .env.production -f docker-compose.prod.yaml'" >> ~/.bashrc
```

Reload it with `source ~/.bashrc`, and then it is just `dc ps`, `dc logs -f`,
`dc exec app sh`.

And for nginx on the VPS:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

```bash
sudo tail -f /var/log/nginx/error.log
```

The first applies changes to a site file safely. The second shows nginx's
errors live.

### Backing up the database

```bash
dc exec db sh -c 'mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' > backup.sql
```

Copy `backup.sql` off the server. Do this before anything risky.

---

## When something goes wrong

**`502 Bad Gateway`**
nginx is working, but nothing answers on the port it passes requests to.
Either the stack is down (`dc ps`), or the port in the nginx site file does not
match `docker-compose.prod.yaml`. Test the stack directly on the server:
`curl http://127.0.0.1:8000/up`. If that works, the site file has the wrong
port.

**`413 Request Entity Too Large`**
An upload was bigger than `client_max_body_size` in the nginx site file. Raise
it there, then `sudo nginx -t && sudo systemctl reload nginx`.

**You see "Welcome to nginx!" instead of your API**
The domain did not match any site, so nginx showed its default page. Check
`server_name` in `/etc/nginx/sites-available/api` is spelled exactly like the
domain, and that the site is linked into `sites-enabled`.

**certbot fails**
Almost always DNS: the domain must already point at this server, and the
Cloudflare record must be grey (DNS only). Port 80 must also be open --
`ufw status` should list `Nginx Full`.

**`Access denied for user 'laravel'` when migrating**
You changed a `DB_` value in `.env.production` after the database was first
created, and MySQL is still using the old login. If there is no data worth
keeping yet, reset only the database:

```bash
dc down
docker volume rm api_mysql-data
./deploy.sh
```

If there is real data, put the original `DB_` values back instead.

**The frontend gets "blocked by CORS policy" in the browser console**
`FRONTEND_URL` on the server does not exactly match the address the browser is
on. It must include `https://` and have no trailing slash. Fix it and run
`./deploy.sh`.

**The frontend calls `localhost` instead of your API**
`NEXT_PUBLIC_API_URL` was missing when Cloudflare built the site. Set it and
redeploy the frontend.

**Forgot the phpMyAdmin password**
Set a new one (no `-c` this time -- `-c` would wipe the file):
`sudo htpasswd /etc/nginx/.htpasswd admin`

**phpMyAdmin loads but says it can't connect to the server**
Check the database is healthy (`dc ps`). The `PMA_HOST` is the container name
`db`, not `localhost` -- localhost inside a container means the container
itself.

**`app` container keeps restarting**
Read `dc logs app`. If the database itself looks wrong, `dc logs db` too.

**Port 80 is already in use when nginx starts**
Something else is on it -- often Apache (`sudo systemctl disable --now apache2`)
or an old Caddy container (`docker ps` to find it).

**Out of disk space**
Old images pile up: `docker system prune -a`.

---

## Reaching phpMyAdmin without opening it to the internet

Publishing phpMyAdmin at `db.yoursite.com` is convenient -- and convenient for
attackers too. The password prompt stops the casual scanning, but a database
admin panel on the public internet is still the riskiest thing in this setup.

The safer option is an **SSH tunnel**. phpMyAdmin already listens on
`127.0.0.1:8001` on the server, so all you do is stop publishing it: delete
the `db.yoursite.com` server block from `/etc/nginx/sites-available/api`,
reload nginx, and drop the `db` DNS record.

Then, from your own computer:

```bash
ssh -L 8001:127.0.0.1:8001 root@203.0.113.10
```

Leave that terminal open and go to **http://localhost:8001** in your browser.
You are looking at phpMyAdmin on the server, through the SSH connection you
already trust. Close the terminal and the door closes with it.

Which to teach? Start with the nginx version because students can see it work
in a browser immediately. Show the tunnel once they are comfortable -- it is
how this is usually done on a real production server.

---

## Switching a server from the old Caddy setup

If this server ran the earlier version, where Caddy was a container in the
stack:

1. `git pull` -- the new `docker-compose.prod.yaml` has no Caddy.
2. `./deploy.sh` -- this also removes the old Caddy container, which frees
   ports 80 and 443. **Your API is offline from here until step 4.**
3. Step 4 of this guide (install nginx and certbot). Do it *after* step 2 --
   nginx needs port 80, and the old Caddy container holds it until then.
4. Steps 8 and 9 (site file, then certbot).

Optionally, remove the old Caddy data afterwards:
`docker volume rm api_caddy-data api_caddy-config`

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

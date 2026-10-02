# socialanxiety

Self-hosted **[Postiz](https://postiz.com)** social-media management, deployed
with Docker Compose behind an auto-HTTPS Caddy reverse proxy, built to run on an
**Oracle Cloud Always-Free** VM and served at **https://post.tasklink.tech**.

This is your working copy of the Postiz deployment stack. You push changes here;
a GitHub Actions pipeline syncs them to the VM automatically.

> Derived from the upstream [gitroomhq/postiz-docker-compose](https://github.com/gitroomhq/postiz-docker-compose)
> template. Postiz itself is AGPL-3.0; the app runs from the prebuilt
> `ghcr.io/gitroomhq/postiz-app` image (not vendored here).

---

## What's in the box

| Service | Purpose | Exposed? |
|---|---|---|
| `caddy` | Reverse proxy + automatic Let's Encrypt HTTPS | **Yes** — 80/443 public |
| `postiz` | The app — frontend **and** backend API (port 5000) | No — only via Caddy |
| `postiz-postgres` | App database | No |
| `postiz-redis` | Cache / queues | No |
| `temporal` + `temporal-postgresql` + `temporal-elasticsearch` + `temporal-ui` | Workflow engine that runs scheduled posts | No (UI on loopback only) |

Postiz serves the **frontend and the backend on the same origin** (`/` and
`/api`), so one proxy rule exposes both remotely — no separate backend host
needed.

### Managing your own pages *and* paying clients

Postiz self-hosted supports this natively:

- **Customer Groups** — organize connected channels per client/brand; each group
  keeps its own channels, calendar, and analytics. This is how you separate your
  own pages from each client's pages.
- **Multi-user / teams** — invite teammates or give clients limited access to
  collaborate and approve posts.

You run **one** instance and manage everyone from it. (If you later want to
*bill clients through Postiz itself* as a reseller SaaS, the Stripe variables
exist for that — but for an agency that just manages client channels, Customer
Groups are all you need.)

---

## Run it locally (evaluate on your own machine)

Want to try Postiz on your own computer before committing to a server? You can.

**You need:** [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running, ~**8 GB+ free RAM** (16 GB comfortable), and ~**10 GB free disk** (images are ~5-6 GB).

```bash
# macOS / Linux / Windows(Git Bash or WSL)
cd ~/Desktop
git clone https://github.com/blitzkrieg267/socialanxiety.git TLPOSTER
cd TLPOSTER
bash scripts/run-local.sh      # checks Docker + RAM, writes .env, starts the stack
```

Then open **http://localhost:4007**, register your account, and explore.

> **What local mode is / isn't:** great for exploring the UI and features. But it
> only runs while your computer is on, lives at `localhost` (not reachable by
> clients), and **most social-network logins require a public HTTPS URL** — so
> connecting real X/LinkedIn/etc. accounts generally won't work from localhost.
> For 24/7 publishing and client access you'll move the same repo to an
> always-on server (see the sections below). Local uses `.env.local.example`;
> the server uses `.env.example`.

**Stop / start:**
```bash
docker compose -f docker-compose.yaml -f docker-compose.local.yaml down   # stop
bash scripts/run-local.sh                                                 # start again
```

---

## Prerequisites (server deployment)

- An Oracle Cloud account (free tier is fine).
- The `post` subdomain available on `tasklink.tech` (managed at Namecheap).
- This repo (`socialanxiety`) on GitHub.

---

## 1. Create the Oracle Cloud VM

**Use an Ampere A1 (ARM) instance — not the 1 GB AMD micro.** This stack runs
Elasticsearch + two Postgres + Redis + Postiz + Caddy and needs real memory.

1. OCI Console → **Compute → Instances → Create instance**.
2. **Image:** Ubuntu 24.04. **Shape:** `VM.Standard.A1.Flex` →
   **4 OCPU / 24 GB** (the full Always-Free Ampere allowance; **2 OCPU / 12 GB**
   is the practical minimum).
3. Add your SSH public key.
4. **Networking — open the ports.** Under the instance's VCN subnet →
   **Security List** (or an NSG), add **Ingress** rules:
   - Source `0.0.0.0/0`, TCP, dest port **80**
   - Source `0.0.0.0/0`, TCP, dest port **443**
   - (port 22 is already open for SSH)
5. Create, and note the **public IP**.

---

## 2. Point the subdomain (Namecheap)

Namecheap → **Domain List → tasklink.tech → Manage → Advanced DNS → Add New Record**:

| Type | Host | Value | TTL |
|---|---|---|---|
| A Record | `post` | `<your VM public IP>` | Automatic |

Wait for it to resolve (usually minutes):

```bash
dig +short post.tasklink.tech   # should print your VM's IP
```

Caddy cannot issue a certificate until this resolves to the VM.

---

## 3. Bootstrap the VM

SSH in (`ssh ubuntu@<vm-ip>`), then:

```bash
# Fetch just the bootstrap script first (repo is private; this clones after).
curl -fsSL https://raw.githubusercontent.com/blitzkrieg267/socialanxiety/main/scripts/bootstrap-vm.sh -o bootstrap-vm.sh
bash bootstrap-vm.sh
```

> Private repo, so the raw URL above needs the repo to allow it — easiest is to
> SSH in and run the equivalent steps, or make the repo public. Either way the
> script: installs Docker, **opens the VM's local iptables firewall for 80/443**
> (Oracle's images block these by default — the #1 reason first deploys fail),
> and prints an SSH **deploy key**.

Add the printed **public** deploy key to GitHub:
**repo → Settings → Deploy keys → Add deploy key** (write access **off**).

---

## 4. Clone, configure, launch

```bash
git clone git@github.com:blitzkrieg267/socialanxiety.git ~/socialanxiety
cd ~/socialanxiety
cp .env.example .env
```

Edit `.env` and set at minimum:

```bash
POSTIZ_DOMAIN=post.tasklink.tech
ACME_EMAIL=you@tasklink.tech
MAIN_URL=https://post.tasklink.tech
FRONTEND_URL=https://post.tasklink.tech
NEXT_PUBLIC_BACKEND_URL=https://post.tasklink.tech/api
JWT_SECRET=$(openssl rand -hex 32)          # paste the output
POSTGRES_PASSWORD=...                        # openssl rand -hex 24
DATABASE_URL=postgresql://postiz-user:<same-password>@postiz-postgres:5432/postiz-db-local
DISABLE_REGISTRATION=false                   # keep false for first boot
```

> **`POSTGRES_PASSWORD` must be identical to the password inside `DATABASE_URL`.**

Launch:

```bash
docker compose up -d
docker compose logs -f postiz     # watch until it's serving on :5000
```

First boot runs DB migrations and can take a couple of minutes.

---

## 5. First login & lockdown

1. Open **https://post.tasklink.tech** — Caddy should have a valid cert.
2. **Register** your admin account immediately.
3. Then lock the door: set `DISABLE_REGISTRATION=true` in `.env` and apply:

   ```bash
   make restart        # (or: docker compose down && docker compose up -d)
   ```

   (Changing env values requires a recreate — a plain restart won't re-read them.)
4. Connect your pages, and create **Customer Groups** for each client.

---

## 6. Continuous deployment (push → VM updates itself)

`.github/workflows/deploy.yml` SSHes into the VM on every push to `main`, runs
`git reset --hard origin/main`, pulls images, and recreates the stack. Your
`.env` is git-ignored, so **deployments never overwrite your secrets**.

### Set it up (one time)

1. **A deploy SSH key GitHub can use to reach the VM.** On your laptop:

   ```bash
   ssh-keygen -t ed25519 -f gha_deploy -N ""
   ssh-copy-id -i gha_deploy.pub ubuntu@<vm-ip>   # or append gha_deploy.pub to the VM's ~/.ssh/authorized_keys
   ```

2. **GitHub → repo → Settings → Secrets and variables → Actions → New secret:**

   | Secret | Value |
   |---|---|
   | `VM_HOST` | VM public IP (or `post.tasklink.tech`) |
   | `VM_SSH_USER` | `ubuntu` |
   | `VM_SSH_KEY` | **private** key contents (`cat gha_deploy`) |
   | `VM_PATH` | `/home/ubuntu/socialanxiety` |
   | `VM_SSH_KNOWN_HOSTS` | *(optional, recommended)* `ssh-keyscan -H <vm-ip>` output |

3. Push to `main` — the **Actions** tab shows the deploy. Trigger manually any
   time via **Actions → Deploy to VM → Run workflow**.

### Your day-to-day workflow

```
edit locally  ->  git push origin main  ->  GitHub Actions  ->  VM updated & restarted
```

On the VM you can also update by hand anytime: `make update`.

> **Alternative (no inbound SSH):** if you'd rather not store an SSH key in
> GitHub, run a pull-based updater on the VM instead — a cron/systemd timer that
> runs `make update` every few minutes. Ask and this repo can ship that unit
> file instead of (or alongside) the Actions pipeline.

---

## Upgrading Postiz

```bash
make update     # pulls the latest postiz-app image and recreates
```

⚠️ Read the [v2.11.2 → v2.12.0 Temporal migration note](https://docs.postiz.com/installation/migration)
before jumping across that boundary.

---

## Operating cheatsheet

```bash
make up        # start        make logs     # tail postiz logs
make down      # stop         make ps       # status
make restart   # apply .env   make update   # pull + redeploy
```

- **Temporal UI** (internal only) — tunnel from your laptop:
  `ssh -L 8080:127.0.0.1:8080 ubuntu@<vm-ip>` then open http://localhost:8080
- **Backups**: snapshot the `postgres-volume` and `postiz-uploads` docker
  volumes (or the whole boot volume via OCI). Postgres + uploads are your state.

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Site unreachable, no cert | OCI ingress rules for 80/443 missing, **or** VM iptables still blocking (re-run bootstrap step 2) |
| Cert fails to issue | `post.tasklink.tech` not resolving to the VM yet (`dig +short post.tasklink.tech`) |
| Login/redirect loops | `MAIN_URL` / `FRONTEND_URL` / `NEXT_PUBLIC_BACKEND_URL` don't exactly match the public https URL |
| DB auth errors on boot | `POSTGRES_PASSWORD` ≠ the password in `DATABASE_URL` |
| OOM / containers killed | Using the 1 GB AMD shape — move to Ampere A1 with ≥12 GB |

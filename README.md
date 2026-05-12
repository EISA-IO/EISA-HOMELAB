<p align="center">
  <img src="GITHUB-LOGO.png" alt="EISA Homelab" width="900">
</p>

# EISA Homelab

> **The ultimate private, no-tracking homelab stack.**
> 100% local-first  ·  zero telemetry  ·  your data on your machine.
>
> Created by **Ahmed Al-EISA**.

A one-machine homelab stack: media (Jellyfin / Navidrome / Immich), files
(Filebrowser), local AI (Ollama + Open WebUI + SearXNG + Local Deep Research +
Vane), workflow automation (n8n), reverse proxy (Caddy), SSO (Authelia),
tunnel (Cloudflared), Tor browser, Portainer, and Heimdall as the landing page.

### Why it's private

- **LLMs run locally.** Ollama hosts every model on your hardware — prompts,
  responses, and embeddings never leave your network.
- **No telemetry.** n8n diagnostics + personalization are forced off; SearXNG
  is configured for zero tracking; nothing in the stack phones home.
- **No third-party AI providers.** Open WebUI, Local Deep Research, and Vane
  all talk to the local Ollama API, not OpenAI / Anthropic / Google.
- **No accounts required.** Everything authenticates against your own
  Authelia instance — there is no cloud sign-up anywhere in the install path.
- **Tor browser included** for the moments you want to leave even your
  home IP behind.
- **Tunnel mode is opt-in.** If you turn it off (the default), the stack is
  unreachable from the public internet — period.

Two ways to run it:

- **Local-only mode** — services reachable only on your LAN by `host:port`.
- **Tunnel mode** — Cloudflare tunnel publishes them on subdomains of a domain
  you own (`hub.example.com`, `chat.example.com`, ...) gated by Authelia SSO.

The unified manager (`WINDOWS-HOMELAB-MANAGER.BAT` / `MAC-HOMELAB-MANAGER.COMMAND`)
walks you through whichever you want, and lets you pick how much of the stack
to run: **AI only**, **Media & Productivity only**, or **Ultimate** (both).

---

## Prerequisites

- **Windows 10/11** with PowerShell 5.1+ (PowerShell 7 / `pwsh` works too) **or
  macOS 12+** with PowerShell 7. The Mac launcher will install `pwsh` via
  Homebrew on first run if it's missing.
- **Docker Desktop** — *not* required up front. If the wizard doesn't find it,
  it will download and install Docker Desktop for you (winget → MSI on Windows,
  Homebrew → DMG on macOS), then resume.
  - For Ollama GPU acceleration on NVIDIA: install the latest NVIDIA driver
    and enable WSL 2 GPU passthrough in Docker Desktop settings.
- **Disk** with the media folders you want to expose. The wizard asks for each
  folder by name (Movies / TV Shows / Music / Downloads).
- **(Tunnel mode only)** A Cloudflare account with a domain on your account
  and a tunnel created at <https://dash.cloudflare.com/>.

---

## Quick start

There is **one entry point per platform**. Everything else lives behind a menu.

| Platform | Launcher | Double-click? |
| --- | --- | --- |
| Windows | `WINDOWS-HOMELAB-MANAGER.BAT` | ✓ |
| macOS   | `MAC-HOMELAB-MANAGER.COMMAND` | ✓ |

```
  EISA HOMELAB ULTIMATE - Manager

   [1] First-Run Setup       (wizard - run me once on a fresh clone)
   [2] Start Stack           (day-to-day, brings everything up)
   [3] Stop Stack            (compose down + cleanup)
   [4] LLM Manager           (pull, launch, delete Ollama models)

   [0] Exit
```

**Windows — fresh clone:**

```bat
git clone https://github.com/EISA-IO/EISA-HOMELAB.git
cd EISA-HOMELAB
WINDOWS-HOMELAB-MANAGER.BAT      :: pick [1] the first time
```

**macOS — fresh clone:**

```sh
git clone https://github.com/EISA-IO/EISA-HOMELAB.git
cd EISA-HOMELAB
./MAC-HOMELAB-MANAGER.COMMAND    # or double-click in Finder; pick [1] the first time
```

### [1] First-Run Setup — what the wizard does, in order

1. Checks Docker Desktop. If it's missing, asks for one-time admin / sudo and
   installs it automatically (winget → MSI fallback on Windows, Homebrew → DMG
   fallback on macOS), waits for the engine to come up, then continues.
2. **Step 1** — pick a stack: `AI ONLY` / `MEDIA & PRODUCTIVITY` / `ULTIMATE`.
3. **Step 2** — pick hosting mode: local-only LAN, or Cloudflare tunnel
   (prompts for your domain + tunnel token if you choose tunnel; includes a
   step-by-step walkthrough of getting the token from
   <https://dash.cloudflare.com/>).
4. **Step 3** *(only if media is in the stack)* — asks in plain language:
   `MOVIES FOLDER LOCATION`, `TV SHOWS FOLDER LOCATION`,
   `MUSIC FOLDER LOCATION`, `DOWNLOADS FOLDER LOCATION`.
5. **Step 4** — silently generates strong random secrets for Postgres, n8n,
   Hermes, Authelia, SearXNG, the Tor browser, etc.
6. Renders `Caddyfile`, `authelia/configuration.yml`, and
   `searxng/settings.yml` from their `.tmpl` templates and brings the right
   docker compose profiles up (`ai`, `media`, plus `tunnel` if applicable).
7. **Step 5** *(only if AI is in the stack and Ollama has no models yet)* —
   shows the LOW/HIGH VRAM picks from `recommended_models.txt` and pulls
   the one you pick.

To change your choices later, the wizard accepts these flags when called
directly from the command line:

```bat
:: Windows: re-run the wizard from the shell (skips the menu)
%PS% -File files\scripts\setup.ps1 -Reconfigure
:: or just open the manager and pick [1] again.
```

### [2] Start Stack

Self-healing. Renders any missing configs, fixes Docker-auto-created stray
dirs at bind-file paths, sets up the Authelia admin user the first time, then
runs `docker compose up -d` with whichever profiles you picked in first-run.

### [3] Stop Stack

`docker compose down --remove-orphans` with all profiles active, plus a
by-`container_name` fallback so containers from older installs (different
compose project names) are also caught.

`docker compose down` stops + removes the containers and the `caddy` network,
but does **not** touch:

- Named docker volumes (so Ollama models, Open WebUI data, Jellyfin cache, etc.
  survive a stop/start cycle).
- Anything under `files/persistent-storage/`.
- Your media on `MOVIES_PATH` / `TV_SHOWS_PATH` / `MUSIC_PATH` / `DOWNLOADS_PATH`.

If you ever want to wipe docker volumes or prune dangling images, run
`docker compose down --volumes` or `docker system prune -f` by hand.

---

## What each app is for (plain English)

Quick tour of every container in the stack, grouped by what it's for.
Skip to the section that matches what you want to do.

### CORE — always installed, you usually don't think about them

- **Heimdall** — your homepage. One web page with tiles for every other
  app, so you don't have to remember port numbers. The first thing you'll
  bookmark.
- **Caddy** — the traffic cop. Routes incoming web requests to the right
  app. You never click on it; it just works in the background.
- **Authelia** — the login page. When you publish your stack online
  (tunnel mode), this is what people log in through. Adds 2FA, group
  permissions, etc. Idle in local-only mode.
- **Portainer** — a web GUI for managing all the Docker containers.
  Useful when you want to look at logs or restart something without
  using the command line.

### AI — local LLMs, private search, automations

- **Ollama** — the engine that runs AI language models on your own
  computer. The chat / search / research apps below all talk to it.
  Nothing ever leaves your machine.
- **Open WebUI** — a ChatGPT-style chat window for talking to the local
  AI. The main app you'll use in this category.
- **SearXNG** — a private search engine. Pulls results from Google /
  Bing / DuckDuckGo without telling them who you are.
- **Local Deep Research** — an AI research assistant. Give it a topic
  and it reads dozens of web pages and writes you a structured report.
  Like a one-person research team that works overnight.
- **Vane** — a "Perplexity-style" answer engine. Type a question, get a
  short answer with sources. Faster than chat for one-shot lookups.
- **n8n** — a drag-and-drop automation builder. You wire up blocks
  ("when an email arrives → save the attachment → ask the AI to
  summarise it → text me the result") into workflows that run on a
  schedule.

### MEDIA — your own Netflix / Spotify / Google Photos

- **Jellyfin** — your own Netflix for movies and TV. Reads from the
  Movies + TV Shows folders you set in the wizard, streams to your TV,
  phone, or browser. Free, no subscription.
- **Navidrome** — your own Spotify for music. Reads from your Music
  folder, streams to phone and browser. Beautiful mobile apps available.
- **Immich** — your own Google Photos. Auto-backup from your phone,
  face / object recognition, search by what's IN the photo, share
  albums. Replaces Google Photos completely.

### PRODUCTIVITY — utilities and one-off tools

- **Filebrowser** — a web file explorer for the folders you exposed
  (movies, music, photos, downloads). Upload, rename, move files from
  any browser without remoting into the machine.
- **Omni Tools** — a grab-bag of small web utilities. Resize images,
  convert file formats, generate QR codes, base64-encode, etc. Like
  the "online tools" sites you've used, but running locally so nothing
  uploads anywhere.
- **Tor Browser** — a full Tor Browser running in your browser tab.
  Opens onion sites and routes through Tor without installing anything
  on your machine. One click from Heimdall.

### ONLINE-ONLY — only runs in tunnel mode

- **Cloudflared** — the secure connector to your Cloudflare account.
  Lets people on the internet reach `chat.yourdomain.com`,
  `movie.yourdomain.com`, etc. without you opening any router ports.
  Excluded automatically in local-only mode.

---

## What's running

| Service          | Local URL                  | Notes |
| ---------------- | -------------------------- | --- |
| Heimdall         | <http://localhost:8080>    | Start page / dashboard |
| Authelia         | <http://localhost:9091>    | SSO (only useful in tunnel mode) |
| Caddy            | <http://localhost:80>      | Reverse proxy (tunnel mode only) |
| Jellyfin         | <http://localhost:9014>    | Movies & TV |
| Navidrome        | <http://localhost:4533>    | Music streaming |
| Immich           | <http://localhost:2283>    | Photo + video library (with face/object recognition; HW-accelerated transcoding + ML when GPU is detected) |
| Filebrowser      | <http://localhost:8095>    | File manager |
| Open WebUI       | <http://localhost:9002>    | LLM frontend |
| Ollama API       | <http://localhost:11434>   | LLM backend |
| SearXNG          | <http://localhost:8031>    | Metasearch (private) |
| Local Deep Research | <http://localhost:5000> | AI research assistant |
| Vane             | <http://localhost:3000>    | AI answer engine |
| n8n              | <http://localhost:5678>    | Workflow automation |
| Portainer        | <http://localhost:9000>    | Container management |
| Tor Browser      | <http://tor.localhost/>    | Zero-click auto-login through Caddy (no kasm prompt). Direct kasm at <https://localhost:6901> still works but asks for the basic-auth password. |
| Omni Tools       | <http://localhost:8890>    | Misc utilities |

**Tor Browser auto-login** — Caddy injects the kasm basic-auth header on
proxied requests AND redirects bare `/` to the auto-connect URL, so the
kasm login form never appears:

- **Local**: `http://tor.localhost/` — `*.localhost` resolves to 127.0.0.1
  on Windows 10+, macOS, and Linux without any hosts-file edits.
- **Tunnel**: `https://tor.<your-domain>/` — same chain, gated by Authelia
  SSO first.

Hitting `https://localhost:6901/` directly still works but bypasses Caddy,
so kasm shows its native basic-auth prompt — use `tor.localhost` instead.

In tunnel mode each service is also reachable behind Authelia at e.g.
`https://chat.example.com`, `https://hub.example.com`, etc. — the
subdomain map is in `files/persistent-storage/caddy/Caddyfile.tmpl` and
`files/persistent-storage/authelia/configuration.yml.tmpl`.

---

## Configuring Authelia users

After the first run, the wizard copies `users_database.yml.example` to
`users_database.yml` if it's not already there. **The placeholder password
hash in that file is invalid on purpose** — Authelia will refuse to start
until you replace it. Generate a real hash with:

```bat
docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password "your-strong-password"
```

Then paste the resulting `$argon2id$...` string into `users_database.yml`
in place of `__ARGON2_HASH_REPLACE_ME__`, and `docker restart Authelia`.

---

## Storage layout

The wizard asks for four user-facing media paths and writes them to `.env`
as absolute paths (forward-slashed for docker compose):

```
${MOVIES_PATH}    -> /media/movies   (Jellyfin)  and /srv/movies   (Filebrowser)
${TV_SHOWS_PATH}  -> /media/tv       (Jellyfin)  and /srv/tv-shows (Filebrowser)
${MUSIC_PATH}     -> /music          (Navidrome) and /srv/music    (Filebrowser)
${DOWNLOADS_PATH} -> /home/kasm-user/Downloads (Tor Browser) and /srv/downloads (Filebrowser)
```

`PERSISTENT_STORAGE` (default `./persistent-storage`, resolved relative to
`files/`) holds container configs and small databases that need to survive
restarts.

---

## Files & folders

```
.
├── WINDOWS-HOMELAB-MANAGER.BAT                  # Windows entry point (menu: first-run / start / stop / LLM mgr)
├── MAC-HOMELAB-MANAGER.COMMAND                  # macOS entry point (same menu)
├── README.md                                    # this file
└── files/                                       # everything else lives here
    ├── .env.example                             # template the wizard copies to files/.env
    ├── docker-compose.yml                       # full stack (profiles: ai, media, tunnel)
    ├── recommended_models.txt                   # LOW/HIGH VRAM model picks for the wizard + LLM_MANAGER
    ├── scripts/
    │   └── setup.ps1                            # the wizard (also handles -StartOnly)
    └── persistent-storage/
        ├── caddy/Caddyfile.tmpl                 # rendered to Caddyfile at startup
        ├── authelia/
        │   ├── configuration.yml.tmpl           # rendered to configuration.yml
        │   └── users_database.yml.example       # copied to users_database.yml on first run
        └── do-not-delete/
            ├── searxng/{settings.yml.tmpl, limiter.toml, uwsgi.ini}
            └── filebrowser/settings.json
```

The rendered runtime files (`Caddyfile`, `configuration.yml`,
`settings.yml`, `users_database.yml`, `.env`) are gitignored — only the
templates are tracked.

---

## Running on a Mac Studio M1 Ultra (or any Apple Silicon)

The full stack runs cleanly on Apple Silicon — **every image in the compose
ships a `linux/arm64` manifest** so Docker Desktop on Mac pulls native ARM
builds with no emulation. M1 Ultra's 20-core CPU and 128 GB unified memory
are more than enough to host all 21 containers comfortably.

**GPU caveat:** Docker Desktop on macOS runs containers inside a Linux VM
that has **no access to Metal**. This is a Docker Desktop limitation, not
something compose can fix. The implication:

| Workload | What happens on Mac |
| --- | --- |
| **Ollama (LLM inference)** | The wizard's GPU step auto-detects this and offers a **NATIVE Ollama** option. With this picked, the in-container `ollama` service is excluded; Open WebUI, Local Deep Research, and Vane are repointed at `http://host.docker.internal:11434` where Mac-native Ollama serves them via Metal. Setup: `brew install ollama && brew services start ollama` (or grab `ollama.app` from <https://ollama.com>). On M1 Ultra this is orders of magnitude faster than CPU inference. |
| **Immich machine learning** | Always CPU on Mac (no Metal-enabled image upstream). Face/object/clip-search inference works fine on M1 Ultra's CPU; just not GPU-accelerated. |
| **Jellyfin transcoding** | Always CPU on Mac. Software ffmpeg is plenty fast on M1 Ultra for most content (4K HDR might struggle). |

**Recommended Docker Desktop settings** (Settings → Resources):

- **CPUs**: at least 8 (M1 Ultra has 20 — give Docker 12+ if you want headroom)
- **Memory**: at least 16 GB (with 128 GB unified, 24-32 GB to Docker is fine)
- **Disk**: 60+ GB for image storage (Immich's ML model image alone is large)
- **VirtioFS** file sharing (faster than legacy gRPC FUSE for the media binds)

**First-time setup is identical to Windows** — `./MAC-HOMELAB-MANAGER.COMMAND`
opens the same menu and runs the same self-healing wizard.

---

## Troubleshooting

- **`Docker engine did not come up within 5 minutes`** — on a freshly auto-installed
  Docker Desktop, Windows usually needs a sign-out or reboot to finish setting
  up WSL2. Sign out / reboot, launch Docker Desktop manually so it can finish
  first-run setup, then run `WINDOWS-HOMELAB-MANAGER.BAT` and pick **[2] Start Stack**.
- **`docker engine is not running`** — start Docker Desktop and re-run.
- **`docker compose up` fails on the `cloudflared` service** — the token
  is wrong, expired, or not for this account. Regenerate at
  <https://dash.cloudflare.com/>, then open the manager and pick **[1] First-Run Setup** again.
- **Authelia keeps restarting** — most likely you forgot to replace
  `__ARGON2_HASH_REPLACE_ME__` in `users_database.yml`. See the section
  above.
- **Ollama can't see the GPU** — make sure NVIDIA drivers are installed
  on the host and that "Use the WSL 2 based engine" + "Enable GPU support"
  are on in Docker Desktop. If you don't have an NVIDIA GPU, change
  `OLLAMA_GPU_DRIVER=nvidia` to something else or remove the `deploy`
  block from the `ollama` service.

---

## Security notes

- Real `.env`, `users_database.yml`, and rendered `Caddyfile` /
  `configuration.yml` / `settings.yml` files are gitignored. Do not commit
  them — they contain tunnel tokens, JWT secrets, encryption keys, and
  password hashes.
- The `tor-browser` container's password comes from `TOR_VNC_PW` in
  `.env` (the wizard generates a random one on first run). The same
  password is baked into the Caddy redirect that auto-logs you in, so
  you never have to type it. If you publish `tor.${DOMAIN}` over the
  tunnel, the Authelia rule (`group: admins`) is what actually keeps it
  private — anyone with the link still hits SSO before kasm.
- In tunnel mode every protected route requires a valid Authelia session
  (group `admins` by default). Only `auth.${DOMAIN}` and `c.${DOMAIN}`
  bypass auth — review `configuration.yml.tmpl` if you change the routing.

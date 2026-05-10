# EISA Homelab Ultimate

A one-machine homelab stack: media (Jellyfin / Navidrome), files (Filebrowser),
local AI (Ollama + Open WebUI + SearXNG + Local Deep Research + Vane), workflow
automation (n8n + Postgres + Qdrant), reverse proxy (Caddy), SSO
(Authelia), tunnel (Cloudflared), Tor browser, Portainer, and Heimdall as the
landing page.

Two ways to run it:

- **Local-only mode** — services reachable only on your LAN by `host:port`.
- **Tunnel mode** — Cloudflare tunnel publishes them on subdomains of a domain
  you own (`hub.example.com`, `chat.example.com`, ...) gated by Authelia SSO.

The wizard in `RUN.bat` walks you through whichever you want.

---

## Prerequisites

- **Windows 10/11** with PowerShell 5.1+ (PowerShell 7 / `pwsh` works too).
- **Docker Desktop** with the Compose v2 plugin (`docker compose ...`).
  - For Ollama GPU acceleration on NVIDIA: install the latest NVIDIA driver
    and enable WSL 2 GPU passthrough in Docker Desktop settings.
- **Disk** with the media folders you want to expose (anything mounted on a
  drive letter works — the wizard asks you which).
- **(Tunnel mode only)** A Cloudflare account with a domain on your account
  and a tunnel created at <https://one.dash.cloudflare.com/>.

---

## Quick start

```bat
git clone https://github.com/EISA-IO/EISA-HOMELAB-ULTIMATE.git
cd EISA-HOMELAB-ULTIMATE
RUN.bat
```

On first run the wizard:

1. Verifies Docker Desktop is running.
2. Bootstraps `.env` from `.env.example`.
3. Asks **local-only** vs **Cloudflare tunnel**, and (for tunnel) prompts for
   your domain + tunnel token.
4. Asks for `STORAGE_DISK` and `PERSISTENT_STORAGE` paths, then optionally
   for each media subfolder.
5. Generates strong random secrets for n8n, Hermes, SearXNG, Authelia,
   Postgres, etc.
6. Renders `Caddyfile`, `authelia/configuration.yml`, and
   `searxng/settings.yml` from their `.tmpl` templates with your domain +
   secrets substituted in.
7. Copies `users_database.yml.example` → `users_database.yml` if you don't
   have one yet (you must edit it and set a real argon2 hash before
   Authelia will start — the wizard prints the exact `docker run` command).
8. Runs `docker compose up -d` (with the `tunnel` profile if applicable).

Subsequent runs skip the prompts and just bring the stack up. To re-prompt
every value:

```bat
RUN.bat --reconfigure
```

To configure without starting:

```bat
RUN.bat --no-start
```

---

## Stopping

```bat
STOP.bat                   :: interactive — asks about volumes / prune
STOP.bat --volumes         :: also wipe docker volumes (destructive!)
STOP.bat --prune           :: also `docker system prune -f`
STOP.bat --volumes --prune :: both, non-interactive
```

`--volumes` only removes named docker volumes (Ollama models, Open WebUI
data, Jellyfin cache, etc.). Your bind-mounted `persistent-storage/` and
your media on `STORAGE_DISK` are never touched.

---

## What's running

| Service          | Local URL                  | Notes |
| ---------------- | -------------------------- | --- |
| Heimdall         | <http://localhost:8080>    | Start page / dashboard |
| Authelia         | <http://localhost:9091>    | SSO (only useful in tunnel mode) |
| Caddy            | <http://localhost:80>      | Reverse proxy (tunnel mode only) |
| Jellyfin         | <http://localhost:9014>    | Movies & TV |
| Navidrome        | <http://localhost:4533>    | Music streaming |
| Filebrowser      | <http://localhost:8095>    | File manager |
| Open WebUI       | <http://localhost:9002>    | LLM frontend |
| Ollama API       | <http://localhost:11434>   | LLM backend |
| SearXNG          | <http://localhost:8031>    | Metasearch (private) |
| Local Deep Research | <http://localhost:5000> | AI research assistant |
| Vane             | <http://localhost:3000>    | AI answer engine |
| n8n              | <http://localhost:5678>    | Workflow automation |
| Qdrant           | <http://localhost:6333>    | Vector DB (used by n8n) |
| Portainer        | <http://localhost:9000>    | Container management |
| Tor Browser      | auto-login URL below       | Anonymous browsing (KasmVNC) — skips the kasm login form |
| Omni Tools       | <http://localhost:8890>    | Misc utilities |

**Tor Browser auto-login** — Caddy redirects bare `/` to a URL that
passes the kasm credentials in query params, so the login form
auto-submits and you land in the desktop:

- Local: `https://localhost:6901/vnc.html?username=kasm_user&password=<TOR_VNC_PW>&autoconnect=true&resize=remote`
  (the wizard prints the exact URL with your password substituted)
- Tunnel: `https://tor.<your-domain>/` — same effect via Caddy redirect.

In tunnel mode each service is also reachable behind Authelia at e.g.
`https://chat.example.com`, `https://hub.example.com`, etc. — the
subdomain map is in `persistent-storage/caddy/Caddyfile.tmpl` and
`persistent-storage/authelia/configuration.yml.tmpl`.

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

All media paths in the compose file are derived from `.env`:

```
${STORAGE_DISK}/${DOWNLOADS_LOCATION}     -> /srv/downloads
${STORAGE_DISK}/${VIDEOS_LOCATION}        -> /srv/videos
${STORAGE_DISK}/${AUDIO_LOCATION}/music   -> /music   (Navidrome, read-only)
${STORAGE_DISK}/${PLEX_LOCATION}          -> /plex    (Jellyfin)
... etc
```

`PERSISTENT_STORAGE` (default `./persistent-storage`) holds container configs
and small databases that need to survive restarts.

---

## Files & folders

```
.
├── .env.example                                # template the wizard copies to .env
├── docker-compose.yml                           # full stack
├── RUN.bat / STOP.bat                           # entry points (delegate to scripts/*.ps1)
├── scripts/
│   ├── setup.ps1                                # the wizard
│   └── stop.ps1                                 # graceful shutdown
└── persistent-storage/
    ├── caddy/Caddyfile.tmpl                     # rendered to Caddyfile at startup
    ├── authelia/
    │   ├── configuration.yml.tmpl               # rendered to configuration.yml
    │   └── users_database.yml.example           # copied to users_database.yml on first run
    └── do-not-delete/
        ├── searxng/{settings.yml.tmpl, limiter.toml, uwsgi.ini}
        └── filebrowser/settings.json
```

The rendered runtime files (`Caddyfile`, `configuration.yml`,
`settings.yml`, `users_database.yml`, `.env`) are gitignored — only the
templates are tracked.

---

## Troubleshooting

- **`docker engine is not running`** — start Docker Desktop and re-run.
- **`docker compose up` fails on the `cloudflared` service** — the token
  is wrong, expired, or not for this account. Regenerate at
  <https://one.dash.cloudflare.com/> and `RUN.bat --reconfigure`.
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

<p align="center">
  <img src="GITHUB-LOGO.png" alt="EISA Homelab" width="900">
</p>

# 🏠 EISA Homelab (Local Netflix, Spotify, Google Photos, Dropbox, ChatGPT, Perplexity, Scheduled Automation)

> 🛡️ **The ultimate private, no-tracking homelab stack.**
> 💻 100% local-first  ·  🔇 zero telemetry  ·  🔐 your data on your machine.
>
> 👤 Created by **Ahmed Al-EISA**.

---

## ✨ What you get

**One wizard. ~20 containers. Zero cloud accounts. Five minutes from `git clone` to a running stack.**

| | Replaces | Apps in the stack |
| :-: | --- | --- |
| 🎬 | Netflix / Spotify / Google Photos | **Jellyfin** · **Navidrome** · **Immich** |
| 🤖 | ChatGPT / Perplexity / research agents | **Open WebUI** · **Vane** · **Local Deep Research** — all running on local **Ollama** |
| 🪽 | a personal AI assistant that *learns* | **NousResearch Hermes** + **Hermes Workspace** web UI, pointed at OmniCoder 2 by default |
| 🔗 | Zapier / Make.com | **n8n** drag-and-drop automation, wired into everything else |
| 🧅 | a clean browser session | **Tor Browser** in a browser tab, one-click auto-login |
| 📂 | Dropbox / a file manager over the LAN | **Filebrowser** + **Omni Tools** + **Portainer** |
| 🌐 | port-forwarding pain | **Cloudflare tunnel** + **Authelia SSO** — opt-in; off by default |

Nothing phones home. Every LLM prompt stays on your hardware. No OpenAI / Anthropic / Google in the install path. SearXNG has tracking disabled. Tunnel mode is opt-in (off by default) — local-only out of the box.

---

## 🚀 Quick start

**One launcher per platform.** Everything else is behind a menu.

```bat
:: Windows
git clone https://github.com/EISA-IO/EISA-HOMELAB.git
cd EISA-HOMELAB
WINDOWS-HOMELAB-MANAGER.BAT          :: or double-click it
```

```sh
# macOS
git clone https://github.com/EISA-IO/EISA-HOMELAB.git
cd EISA-HOMELAB
./MAC-HOMELAB-MANAGER.COMMAND        # or double-click in Finder
```

That opens this menu:

```
  EISA HOMELAB - Manager
   [1] First-Run Setup    (wizard - run once on a fresh clone)
   [2] Start Stack        (day-to-day, brings everything up)
   [3] Stop Stack         (compose down + cleanup)
   [4] LLM Manager        (pull / launch / delete Ollama models)
   [0] Exit
```

The first-run wizard:
- 🐳 Auto-installs **Docker Desktop** if it's missing (winget / MSI on Windows, brew / DMG on macOS) — one UAC / sudo prompt and it resumes.
- 🧱 Asks which stack: **AI**, **Media**, **Productivity**, **Ultimate**, or **Custom** (pick individual apps).
- 🌐 Asks hosting mode: **local-only** (default) or **Cloudflare tunnel** — walks you through getting a tunnel token if you choose tunnel.
- 📁 Asks where your media lives in plain English (Movies, TV Shows, Music, Downloads, Photos).
- 🔑 Generates every secret + Authelia argon2 hash silently.
- 🧠 If AI is in the stack, auto-installs two starter LLMs (see [The LLMs](#-the-recommended-llms) below).

After that, day-to-day is `[2] Start Stack` / `[3] Stop Stack`. Stopping never touches your media folders or the docker named volumes — Ollama models, Open WebUI history, Jellyfin cache, etc. all survive.

---

## 🎯 What each app does (plain English)

### 🏗️ CORE — always on, you usually don't think about them

- 🏠 **Heimdall** — your homepage. Tiles for every other app, so you don't remember port numbers.
- 🚦 **Caddy** — the traffic cop. Routes requests to the right app. You never click on it.
- 🔐 **Authelia** — the login page (tunnel mode). 2FA + group permissions.
- 🎛️ **Portainer** — a Docker web GUI for when you want to look at logs or restart something.

### 🤖 AI — local LLMs, private search, agents, automation

- 🧠 **Ollama** — the engine running AI language models on your own hardware. Everything below talks to it.
- 💬 **Open WebUI** — a ChatGPT-style chat window. The main app you'll open.
- 🔍 **SearXNG** — a private metasearch engine. Google / Bing / DuckDuckGo results without the tracking.
- 📚 **Local Deep Research** — give it a topic, get a structured report. Like a researcher that works overnight.
- ❓ **Vane** — a Perplexity-style answer engine. One-shot questions with sources.
- 🪽 **Hermes** — NousResearch's self-improving agent with persistent memory + skill creation, paired with the **Hermes Workspace** web UI (chat, memory browser, terminal, swarm view). Default model: OmniCoder 2.
- 🔗 **n8n** — drag-and-drop automation. *"When an email arrives → save the attachment → ask the AI to summarise it → text me the result."*

### 🎬 MEDIA — your own Netflix / Spotify / Google Photos

- 🎥 **Jellyfin** — Netflix for your movies and TV. Reads from the folder you set, streams to TV / phone / browser.
- 🎵 **Navidrome** — Spotify for your music. Same idea. Beautiful mobile apps available.
- 📸 **Immich** — Google Photos replacement. Phone auto-backup, face / object recognition, search by what's *in* the photo.

### 🛠️ PRODUCTIVITY — utilities

- 📂 **Filebrowser** — web file explorer for the folders you exposed. Upload / rename / move from any browser.
- 🧰 **Omni Tools** — local versions of every "online tool" site (resize, convert, QR, base64, …) — nothing leaves your machine.
- 🧅 **Tor Browser** — full Tor Browser in a browser tab. One click from Heimdall.

### 🌐 ONLINE-ONLY — only in tunnel mode

- ☁️ **Cloudflared** — connects your stack to Cloudflare so people can reach `chat.yourdomain.com`, `movie.yourdomain.com`, etc. without you opening router ports.

---

## 🗺️ Service URLs (local mode)

| Service | URL | Service | URL |
| --- | --- | --- | --- |
| Heimdall | <http://localhost:8080> | Open WebUI | <http://localhost:9002> |
| Jellyfin | <http://localhost:9014> | SearXNG | <http://localhost:8031> |
| Navidrome | <http://localhost:4533> | Local Deep Research | <http://localhost:5000> |
| Immich | <http://localhost:2283> | Vane | <http://localhost:3000> |
| Filebrowser | <http://localhost:8095> | Hermes Workspace | <http://localhost:3030> |
| Omni Tools | <http://localhost:8890> | Hermes Gateway | <http://localhost:8642> |
| Tor Browser | <http://tor.localhost/> | n8n | <http://localhost:5678> |
| Portainer | <http://localhost:9000> | Ollama API | <http://localhost:11434> |

In tunnel mode everything also gets a subdomain on your own domain (`chat.example.com`, `movie.example.com`, …) gated by Authelia SSO.

---

## 🧠 The recommended LLMs

The wizard auto-installs two starter models so you're not staring at an empty chat box. Two heavier "monsters" sit in `recommended_models.txt` for when you have the hardware — pull them from `[4] LLM Manager` in the launcher.

### 📦 Starters (auto-installed, ~5 GB each, runs on almost any GPU/CPU)

- **🌟 `huihui_ai/gemma-4-abliterated:e4b-q4_K`** — General-purpose, uncensored.
  Google's Gemma 4 (4B) with the refusal layer surgically removed (no retraining, just no more "I can't help with that"). Daily-driver for chat / writing / Q&A.
- **👨‍💻 `carstenuhlig/omnicoder-2-9b:q4_k_m`** — Agentic + coding.
  9B fine-tune built for code generation and tool-use. Use for anything code-shaped or when you want the model to plan + execute multi-step work. Pairs cleanly with n8n's AI nodes.

### 💪 Monsters (manual pull, ~16-24 GB VRAM)

- **🦣 `iaprofesseur/SuperGemma4-26b-uncensored-Q4`** — 26B uncensored Gemma 4. Same family as the small starter, much bigger brain. For long-form writing / sustained reasoning.
- **🐲 `fredrezones55/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive:Q4`** — 35B Qwen MoE, aggressive uncensored finetune. **MoE** = 35B total params, only ~3B *active* per token — runs at the speed of a small model with the reasoning of a huge one. The closest you'll get to a frontier model on your own GPU.

> **Glossary** — *VRAM*: your GPU's memory budget. *Quantization* (`q4_K`, `Q4_K_M`): how the weights are compressed; smaller = faster, slight quality cost. *Abliterated*: refusal removed via weight surgery; the model isn't retrained or dumbed down. *MoE*: many "experts" inside; only a couple activate per token, so total params >> active params.

---

## ⚙️ Notes

- **Linux containers run on Apple Silicon** — every image is multi-arch (`linux/arm64`). Docker on Mac can't pass Metal through to containers, so the wizard offers a "**Native Ollama**" mode that points Open WebUI / LDR / Vane at the host's Metal-accelerated `brew install ollama`.
- **GPU acceleration is pluggable** — the wizard detects NVIDIA / AMD / CPU and layers the right compose override on top. Same detection drives Immich's NVENC / VAAPI transcoding + ML acceleration.
- **Authelia admin password** is auto-generated and stored in `files/.env` as `AUTHELIA_ADMIN_PASSWORD` (username: `admin`). Same pattern for Hermes Workspace (`HERMES_WORKSPACE_PASSWORD`).
- **Re-configure later** — open the launcher → `[1] First-Run Setup` again. Existing data survives.
- **Manual stop** — `cd files && docker compose down`. The launcher's `[3]` does this + a by-`container_name` fallback so containers from older installs are also caught.

---

## 🔒 Security

- Real `.env`, `users_database.yml`, and rendered configs (`Caddyfile`, `configuration.yml`, `settings.yml`) are gitignored — they contain tokens, secrets, encryption keys, and password hashes. Never commit them.
- In tunnel mode every protected route requires a valid Authelia session (group `admins` by default). Only `auth.${DOMAIN}` and `c.${DOMAIN}` bypass.
- The Hermes dashboard sits on the internal docker network only (not host-exposed) — it surfaces API keys without auth; only the workspace reaches it.

---

## 🙏 Credits

Built on the shoulders of [Jellyfin](https://jellyfin.org), [Navidrome](https://www.navidrome.org), [Immich](https://github.com/immich-app/immich), [Filebrowser](https://github.com/filebrowser/filebrowser), [Ollama](https://ollama.com), [Open WebUI](https://github.com/open-webui/open-webui), [SearXNG](https://github.com/searxng/searxng), [Local Deep Research](https://github.com/LearningCircuit/local-deep-research), [Vane](https://github.com/itzcrazykns1337/Vane), [NousResearch Hermes Agent](https://github.com/NousResearch/hermes-agent), [Hermes Workspace](https://github.com/outsourc-e/hermes-workspace), [n8n](https://n8n.io), [Caddy](https://caddyserver.com), [Authelia](https://www.authelia.com), [Cloudflared](https://github.com/cloudflare/cloudflared), [Portainer](https://www.portainer.io), [Heimdall](https://heimdall.site), and [KasmVNC Tor Browser](https://hub.docker.com/r/kasmweb/tor-browser).

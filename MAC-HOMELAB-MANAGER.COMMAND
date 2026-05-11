#!/usr/bin/env bash
# =============================================================================
# EISA HOMELAB ULTIMATE - Unified manager (macOS)
# Mirror of WINDOWS-HOMELAB-MANAGER.BAT. Menu-driven, single entry point:
#   [1] First-Run Setup    (wizard - once on a fresh clone)
#   [2] Start Stack        (day-to-day; brings the chosen profiles up)
#   [3] Stop Stack         (compose down + by-name fallback)
#   [4] LLM Manager        (pull / launch / delete Ollama models)
# =============================================================================
set -u
cd "$(dirname "$0")"

BASE="$(pwd)"
COMPOSE_DIR="${BASE}/files"
SETUP_PS1="${COMPOSE_DIR}/scripts/setup.ps1"
ENV_FILE="${COMPOSE_DIR}/.env"
CONTAINER="ollama"
API="http://127.0.0.1:11434"
CFG="${COMPOSE_DIR}/context_size.cfg"
RECFILE="${COMPOSE_DIR}/recommended_models.txt"

# Green/dim/red ANSI styling so the look matches the Windows bat.
GREEN=$'\033[1;32m'
DIM=$'\033[0;32m'
RED=$'\033[1;31m'
RESET=$'\033[0m'

CTX=""

say() { printf '%s%s%s\n' "${GREEN}" "$1" "${RESET}"; }
dim() { printf '%s%s%s\n' "${DIM}"   "$1" "${RESET}"; }
err() { printf '%s%s%s\n' "${RED}"   "$1" "${RESET}"; }

header() {
    echo
    say "  +===================================================+"
    say "   $1"
    say "  +===================================================+"
    echo
}

pause_close() {
    if [ -t 0 ] && [ -z "${SSH_CONNECTION:-}" ]; then
        read -r -p "  Press return to close this window..." _ || true
    fi
}

pause_return() {
    read -r -p "  Press return to return to the main menu..." _ || true
}

# ============================================================================
# Preflight: pwsh required (for setup.ps1). If missing, try Homebrew.
# ============================================================================
ensure_pwsh() {
    if command -v pwsh >/dev/null 2>&1; then return 0; fi
    err "  PowerShell 7 (pwsh) is required by setup.ps1."
    if command -v brew >/dev/null 2>&1; then
        echo "  Installing it via Homebrew (one-time)..."
        brew install --cask powershell
        return $?
    fi
    echo
    echo "  Homebrew (brew) is not installed."
    echo "  Install Homebrew first:  https://brew.sh"
    echo "  Or install PowerShell manually from:"
    echo "    https://github.com/PowerShell/PowerShell/releases"
    return 1
}

# ============================================================================
# TOP-LEVEL MENU
# ============================================================================
main_menu() {
    while true; do
        clear
        echo
        say "  ============================================================"
        say "   EISA HOMELAB ULTIMATE - Manager"
        say "  ============================================================"
        echo
        echo "   The ULTIMATE private, no-tracking homelab stack."
        echo "   100% local-first  |  zero telemetry  |  your data, your machine"
        echo
        dim "  ------------------------------------------------------------"
        echo
        say "   [1] First-Run Setup       (wizard - run me once on a fresh clone)"
        say "   [2] Start Stack           (day-to-day, brings everything up)"
        say "   [3] Stop Stack            (compose down + cleanup)"
        say "   [4] LLM Manager           (pull, launch, delete Ollama models)"
        echo
        say "   [0] Exit"
        echo
        local choice
        read -r -p "  Select option: " choice
        case "${choice}" in
            1) do_first_run ;;
            2) do_start ;;
            3) do_stop ;;
            4) ollama_boot ;;
            0) return 0 ;;
        esac
    done
}

# ============================================================================
# [1] FIRST-RUN WIZARD
# ============================================================================
do_first_run() {
    clear
    header "First-run wizard"
    if ! ensure_pwsh; then pause_return; return; fi
    if [ ! -f "${SETUP_PS1}" ]; then
        err "  [X] Could not find setup.ps1 at:"
        echo "      ${SETUP_PS1}"
        echo "      Re-clone or restore files/scripts/."
        pause_return
        return
    fi
    echo "  Wizard: ${SETUP_PS1}"
    echo
    echo "  ----------------------------------------------------------------"
    pwsh -NoProfile -File "${SETUP_PS1}"
    local rc=$?
    echo "  ----------------------------------------------------------------"
    echo
    if [ "${rc}" = "0" ]; then
        say "  [OK] Wizard completed."
    else
        err "  [!]  Wizard exited with code ${rc}."
    fi
    echo
    pause_return
}

# ============================================================================
# [2] START STACK
# ============================================================================
do_start() {
    clear
    header "Starting"
    if ! ensure_pwsh; then pause_return; return; fi
    if [ ! -f "${SETUP_PS1}" ]; then
        err "  [X] setup.ps1 not found at ${SETUP_PS1}"
        pause_return
        return
    fi
    echo "  Wizard in -StartOnly mode (self-healing): renders configs, fixes"
    echo "  bind-mount dirs, sets up the Authelia admin user, runs compose up."
    echo "  ----------------------------------------------------------------"
    pwsh -NoProfile -File "${SETUP_PS1}" -StartOnly
    local rc=$?
    echo "  ----------------------------------------------------------------"
    echo
    if [ "${rc}" = "0" ]; then
        say "  [OK] Stack started."
    else
        err "  [!]  Wizard exited with code ${rc}."
        echo  "       Common cause: containers from an older install are blocking"
        echo  "       these container_names. Pick [3] Stop Stack first, then retry."
    fi
    echo
    pause_return
}

# ============================================================================
# [3] STOP STACK
# ============================================================================
do_stop() {
    clear
    header "Stopping"

    if [ ! -d "${COMPOSE_DIR}" ]; then
        err "  [X] Could not find ${COMPOSE_DIR}"
        pause_return
        return
    fi

    echo "  [1/3] docker compose down --remove-orphans  (project: eisa-homelab)"
    echo "        ----------------------------------------------------------------"
    (
        cd "${COMPOSE_DIR}"
        COMPOSE_PROFILES=ai,media,tunnel docker compose down --remove-orphans
    )
    echo "        ----------------------------------------------------------------"
    echo

    local -a EISA=(
        cloudflared heimdall-media Caddy Authelia navidrome jellyfin
        filebrowser omni-tools n8n qdrant ollama open-webui searxng
        local-deep-research vane Portainer tor-browser
    )

    echo "  [2/3] Stopping any leftover containers by name..."
    for name in "${EISA[@]}"; do
        if docker inspect -f '{{.State.Running}}' "${name}" >/dev/null 2>&1; then
            docker stop "${name}" >/dev/null 2>&1 && echo "         stopped  ${name}"
            docker rm   "${name}" >/dev/null 2>&1 && echo "         removed  ${name}"
        elif docker inspect -f '{{.Id}}' "${name}" >/dev/null 2>&1; then
            docker rm "${name}" >/dev/null 2>&1 && echo "         removed  ${name}  (was stopped)"
        fi
    done
    while IFS= read -r cid; do
        [ -z "${cid}" ] && continue
        docker rm -f "${cid}" >/dev/null 2>&1 && echo "         removed  ${cid}  (n8n-postgres match)"
    done < <(docker ps -aq --filter "name=n8n-postgres" 2>/dev/null)
    echo

    echo "  [3/3] Removing the 'caddy' docker network if it's empty..."
    docker network rm caddy >/dev/null 2>&1 && echo "         removed network 'caddy'"
    echo

    say "  [OK] Stop complete."
    echo
    echo "  Note: bind-mounted media + files/persistent-storage are NOT touched."
    echo "        Named docker volumes are NOT touched."
    echo
    pause_return
}

# ============================================================================
# [4] OLLAMA / LLM MANAGER
# ============================================================================
ollama_boot() {
    if ! command -v docker >/dev/null 2>&1; then
        clear
        header "ERROR"
        err "  docker CLI not found in PATH."
        echo "  Install Docker Desktop and re-run."
        pause_return
        return
    fi
    if ! docker info --format '{{.ServerVersion}}' >/dev/null 2>&1; then
        clear
        header "ERROR"
        err "  Docker engine is not running."
        echo "  Start Docker Desktop and re-run."
        pause_return
        return
    fi

    [ -f "${CFG}" ] || echo 8192 > "${CFG}"
    CTX="$(cat "${CFG}" 2>/dev/null || true)"
    [[ "${CTX}" =~ ^[1-9][0-9]*$ ]] || CTX=8192

    if [ ! -f "${RECFILE}" ]; then
        cat > "${RECFILE}" <<'EOF'
LOW|huihui_ai/gemma-4-abliterated:e4b-q4_K
LOW|huihui_ai/gemma-4-abliterated:e4b-q8_0
HIGH|carstenuhlig/omnicoder-2-9b:q4_k_m
EOF
    fi

    if ! ollama_ensure_container; then return; fi
    ollama_menu
}

api_ready() { curl -sf --max-time 2 "${API}/api/tags" >/dev/null 2>&1; }

ollama_ensure_container() {
    local running i
    running="$(docker inspect -f '{{.State.Running}}' "${CONTAINER}" 2>/dev/null || true)"
    if [ "${running}" = "true" ]; then
        for i in $(seq 1 15); do
            api_ready && return 0
            sleep 1
        done
    fi
    clear
    header "STARTING OLLAMA CONTAINER"
    echo "  Container  : ${CONTAINER}"
    echo "  Compose dir: ${COMPOSE_DIR}"
    echo
    ( cd "${COMPOSE_DIR}" && COMPOSE_PROFILES=ai docker compose up -d "${CONTAINER}" )
    for i in $(seq 1 60); do
        sleep 1
        if api_ready; then
            say "  Ollama API is responding."
            ollama_unload_vram
            echo
            return 0
        fi
    done
    err "  [!] Ollama container did not become ready within 60s."
    echo "      Check: docker logs ${CONTAINER}"
    pause_return
    return 1
}

ollama_unload_vram() {
    local body names name
    body="$(curl -sf --max-time 3 "${API}/api/ps" 2>/dev/null || true)"
    names="$(printf '%s' "${body}" | tr ',' '\n' | grep -oE '"name":"[^"]+"' | sed 's/^"name":"//; s/"$//')"
    if [ -n "${names}" ]; then
        while IFS= read -r name; do
            [ -z "${name}" ] && continue
            echo "  Unloading: ${name}"
            curl -sf -X POST -H 'Content-Type: application/json' \
                -d "{\"model\":\"${name}\",\"keep_alive\":0}" \
                "${API}/api/generate" >/dev/null 2>&1 || true
        done <<< "${names}"
        say "  VRAM freed."
        sleep 2
    else
        echo "  No models loaded in VRAM."
    fi
}

ollama_list_installed() {
    docker exec "${CONTAINER}" ollama list 2>/dev/null | tail -n +2 | awk '
        NF >= 3 {
            name=$1
            if ($3 ~ /^[0-9.]+$/ && $4 ~ /^[KMGT]?B$/) { size=$3" "$4 } else { size=$3 }
            print name"|"size
        }
    '
}

ollama_is_installed() {
    docker exec "${CONTAINER}" ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -qx "$1"
}

ollama_total_size_gb() {
    local body bytes
    body="$(curl -sf --max-time 3 "${API}/api/tags" 2>/dev/null || true)"
    bytes="$(printf '%s' "${body}" | grep -oE '"size":[0-9]+' | awk -F: '{ s += $2 } END { print s+0 }')"
    awk -v b="${bytes:-0}" 'BEGIN { printf "%.2f", b/1073741824 }'
}

ollama_menu() {
    while true; do
        clear
        header "OLLAMA MANAGER (docker)"
        local ver size
        ver="$(docker exec "${CONTAINER}" ollama --version 2>/dev/null || true)"
        [ -z "${ver}" ] && ver="unknown"
        size="$(ollama_total_size_gb)"
        echo "  Container: ${CONTAINER}"
        echo "  Version  : ${ver}"
        echo "  API      : ${API}"
        echo "  Context  : ${CTX}"
        echo
        echo "  Total downloaded Models Size: ${size} GB"
        echo
        say  "  [1] Launch a Model"
        say  "  [2] Pull a Recommended/Custom Model"
        say  "  [3] Delete a Model"
        say  "  [4] Modify Context Length"
        say  "  [0] Back to main menu"
        echo
        local choice
        read -r -p "  Select option: " choice
        case "${choice}" in
            1) ollama_launch ;;
            2) ollama_pull_menu ;;
            3) ollama_delete ;;
            4) ollama_context ;;
            0) return ;;
        esac
    done
}

ollama_launch() {
    ollama_ensure_container || return
    clear
    header "LAUNCH A MODEL"
    local -a names sizes
    while IFS='|' read -r name size; do
        [ -z "${name}" ] && continue
        names+=("${name}")
        sizes+=("${size}")
    done < <(ollama_list_installed)
    if [ "${#names[@]}" -eq 0 ]; then
        echo "  No installed models in the ${CONTAINER} container."
        echo "  Pull one first via menu option [2]."
        echo
        pause_return
        return
    fi
    local i
    for i in "${!names[@]}"; do
        printf '  [%d] %-50s <%s>\n' "$((i+1))" "${names[$i]}" "${sizes[$i]}"
    done
    echo
    say  "  [0] Back"
    echo
    local pick
    read -r -p "  Select model: " pick
    [ -z "${pick}" ] && return
    [ "${pick}" = "0" ] && return
    if ! [[ "${pick}" =~ ^[1-9][0-9]*$ ]] || [ "${pick}" -gt "${#names[@]}" ]; then
        err "  [!] Invalid selection."
        sleep 1
        return
    fi
    local model="${names[$((pick-1))]}"
    clear
    header "LAUNCHING MODEL"
    echo "  Tag       : ${model}"
    echo "  Container : ${CONTAINER}"
    echo "  Context   : ${CTX}"
    echo
    dim "  Inside the REPL: /set parameter num_ctx ${CTX}  (per-session override)"
    dim "  Type /bye to exit and return to the menu."
    echo
    local -a flags=()
    [[ "${model}" == *qwen3.5* ]] && flags+=(--think=false)
    docker exec -it "${CONTAINER}" ollama run "${flags[@]}" "${model}" || true
}

ollama_pull_menu() {
    ollama_ensure_container || return
    while true; do
        clear
        header "PULL A RECOMMENDED/CUSTOM MODEL"
        say  "  [1] Recommended Models"
        say  "  [2] Custom Model Tag"
        say  "  [0] Back"
        echo
        local choice
        read -r -p "  Select option: " choice
        case "${choice}" in
            1) ollama_pull_recommended; return ;;
            2) ollama_pull_custom; return ;;
            0) return ;;
        esac
    done
}

ollama_pull_recommended() {
    clear
    header "PULL RECOMMENDED MODEL"
    local -a tags
    local last_group="" count=0
    while IFS='|' read -r grp tag; do
        [ -z "${tag}" ] && continue
        ollama_is_installed "${tag}" && continue
        if [ "${grp}" != "${last_group}" ]; then
            echo
            [ "${grp}" = "LOW" ]  && dim "  LOW VRAM"
            [ "${grp}" = "HIGH" ] && dim "  HIGH VRAM"
            dim "  --------------------------------------------------------------------------------"
            last_group="${grp}"
        fi
        count=$((count + 1))
        tags+=("${tag}")
        printf '  [%d] %s\n' "${count}" "${tag}"
    done < <(grep -v '^[[:space:]]*$' "${RECFILE}" | grep -v '^#')
    if [ "${count}" -eq 0 ]; then
        echo "  All recommended models are already installed in the container."
        echo
        pause_return
        return
    fi
    echo
    say  "  [0] Back"
    echo
    local pick
    read -r -p "  Select option: " pick
    [ -z "${pick}" ] && return
    [ "${pick}" = "0" ] && return
    if ! [[ "${pick}" =~ ^[1-9][0-9]*$ ]] || [ "${pick}" -gt "${count}" ]; then
        err "  [!] Invalid selection."
        sleep 1
        return
    fi
    local model="${tags[$((pick-1))]}"
    clear
    header "DOWNLOADING MODEL"
    echo "  Pulling ${model} into ${CONTAINER}..."
    echo
    docker exec -it "${CONTAINER}" ollama pull "${model}" || true
    echo
    pause_return
}

ollama_pull_custom() {
    clear
    header "PULL CUSTOM MODEL"
    local model
    read -r -p "  Enter model tag: " model
    [ -z "${model}" ] && return
    echo
    echo "  Pulling ${model} into ${CONTAINER}..."
    echo
    docker exec -it "${CONTAINER}" ollama pull "${model}" || true
    echo
    pause_return
}

ollama_delete() {
    clear
    header "DELETE A MODEL"
    local -a names sizes
    while IFS='|' read -r name size; do
        [ -z "${name}" ] && continue
        names+=("${name}")
        sizes+=("${size}")
    done < <(ollama_list_installed)
    if [ "${#names[@]}" -eq 0 ]; then
        echo "  No installed models in the ${CONTAINER} container."
        echo
        pause_return
        return
    fi
    local i
    for i in "${!names[@]}"; do
        printf '  [%d] %-50s <%s>\n' "$((i+1))" "${names[$i]}" "${sizes[$i]}"
    done
    echo
    say  "  [0] Back"
    echo
    local pick
    read -r -p "  Select model to delete: " pick
    [ -z "${pick}" ] && return
    [ "${pick}" = "0" ] && return
    if ! [[ "${pick}" =~ ^[1-9][0-9]*$ ]] || [ "${pick}" -gt "${#names[@]}" ]; then
        err "  [!] Invalid selection."
        sleep 1
        return
    fi
    local model="${names[$((pick-1))]}"
    echo
    echo "  You are about to delete: ${model}"
    echo
    local confirm
    read -r -p "  Are you sure? [y/N]: " confirm
    case "${confirm}" in y|Y|yes|YES) ;; *) return ;; esac
    echo
    echo "  Removing ${model} from ${CONTAINER}..."
    if docker exec "${CONTAINER}" ollama rm "${model}"; then
        say "  [OK] ${model} deleted successfully."
        sleep 2
    else
        err "  [!] Failed to delete model."
        pause_return
    fi
}

ollama_context() {
    while true; do
        clear
        header "MODIFY CONTEXT LENGTH"
        echo "  Current: ${CTX}"
        echo
        say  "  [1] 4096"
        say  "  [2] 8192"
        say  "  [3] 16384"
        say  "  [4] 32768"
        say  "  [5] 65536"
        say  "  [6] 131072   (128K)"
        say  "  [7] 262144   (256K)"
        say  "  [8] Custom"
        say  "  [0] Back"
        echo
        local pick newctx
        read -r -p "  Select option: " pick
        case "${pick}" in
            1) newctx=4096 ;;
            2) newctx=8192 ;;
            3) newctx=16384 ;;
            4) newctx=32768 ;;
            5) newctx=65536 ;;
            6) newctx=131072 ;;
            7) newctx=262144 ;;
            8)
                echo
                read -r -p "  Enter custom context length: " newctx
                [ -z "${newctx}" ] && continue
                [[ "${newctx}" =~ ^[1-9][0-9]*$ ]] || continue
                ;;
            0) return ;;
            *) continue ;;
        esac
        clear
        header "APPLY CONTEXT LENGTH"
        echo "  Current : ${CTX}"
        echo "  New     : ${newctx}"
        echo
        echo "  Saved locally in context_size.cfg."
        echo
        echo "  Choose Y to also write OLLAMA_NUM_CTX in .env and recreate the"
        echo "  ollama container (server-side default; ~10s downtime)."
        echo
        local recreate
        read -r -p "  Recreate container with new server-side default? [y/N]: " recreate
        CTX="${newctx}"
        echo "${CTX}" > "${CFG}"
        case "${recreate}" in y|Y|yes|YES) ollama_apply_ctx_to_env ;; esac
        return
    done
}

ollama_apply_ctx_to_env() {
    if [ ! -f "${ENV_FILE}" ]; then
        err "  [!] Cannot find ${ENV_FILE} - saving CTX in cfg only."
        pause_return
        return
    fi
    if grep -q '^OLLAMA_NUM_CTX=' "${ENV_FILE}"; then
        sed -i.bak "s|^OLLAMA_NUM_CTX=.*|OLLAMA_NUM_CTX=${CTX}|" "${ENV_FILE}"
        rm -f "${ENV_FILE}.bak"
    else
        printf '\nOLLAMA_NUM_CTX=%s\n' "${CTX}" >> "${ENV_FILE}"
    fi
    clear
    header "RECREATING OLLAMA CONTAINER"
    ( cd "${COMPOSE_DIR}" && COMPOSE_PROFILES=ai docker compose up -d --force-recreate "${CONTAINER}" )
    ollama_ensure_container
}

# ============================================================================
# Entry point
# ============================================================================
clear
main_menu
echo
pause_close
exit 0

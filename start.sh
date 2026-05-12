#!/bin/bash

APPID=4129620
GAMENAME="Windrose"
README_URL="https://git.riyria.xyz/rhavin/windrose/raw/branch/main/README.md"

BINARY="R5/Binaries/Win64/WindroseServer-Win64-Shipping.exe"
GAMEBASE="R5"
GAMEBASEDIR="${GAMEBASE}/Saved"
SAVEDFOLDERS=("Config" "Logs" "SaveProfiles")
FIRSTRUNCHECKFILE="WindroseServer.exe"

OK='✅: \033[1;92m'
INFO='➡️: \033[1;94m'
WARN='⚠️: \033[1;93m'
ERR='❌: \033[1;91m'
HILITE='👉: \033[38;5;208m'
NC='\033[0m'

TZ="${TZ:-UTC}"
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
SKIP_UPDATE="${SKIP_UPDATE:-0}"
GAME_PORT="${GAME_PORT:-7777}"
REMOVE_SERVER_FILES="${REMOVE_SERVER_FILES:-0}"

if ! [[ "${PUID}" =~ ^[0-9]+$ ]] || ! [[ "${PGID}" =~ ^[0-9]+$ ]]; then
  echo -e "${ERR}PUID and PGID must be numeric (got PUID='${PUID}', PGID='${PGID}')${NC}"
  exit 1
fi

if getent group steam >/dev/null; then
  groupmod -o -g "${PGID}" steam >/dev/null 2>&1
else
  groupadd -o -g "${PGID}" steam >/dev/null 2>&1
fi

if id steam >/dev/null 2>&1; then
  usermod -o -u "${PUID}" -g "${PGID}" steam >/dev/null 2>&1
else
  useradd -o -u "${PUID}" -g "${PGID}" -ms /bin/bash steam >/dev/null 2>&1
fi

chown -R steam:steam "${SERVERHOME}"
chown -R steam:steam "${GAMEDATA}"

echo "${TZ}" > /etc/timezone 2>&1
ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime 2>&1
dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1

settings=$(cat<<EOF

${HILITE}Please see the README for this container at: ${README_URL}${NC}

Container Settings:
-------------------
 TZ:                  ${INFO}${TZ}${NC}
 PUID:                ${INFO}${PUID}${NC}
 PGID:                ${INFO}${PGID}${NC}
 SKIP_UPDATE:         $(if [[ "${SKIP_UPDATE}" == "1" ]]; then echo -e "${WARN}1 WARNING: Server files will not update${NC}"; else echo -e "${INFO}0${NC}"; fi)
 REMOVE_SERVER_FILES: $(if [[ "${REMOVE_SERVER_FILES}" == "1" ]]; then echo -e "${WARN}1${NC} ${HILITE}!! UNSET FOR NEXT LAUNCH !!${NC}"; else echo -e "${INFO}0${NC}"; fi)
 SERVERHOME:          ${INFO}${SERVERHOME}${NC}
 GAMEDATA:            ${INFO}${GAMEDATA}${NC}

Server Settings:
----------------
 SERVER_NAME:         ${INFO}${SERVER_NAME:-"(not set, using existing)"}${NC}
 INVITE_CODE:         ${INFO}${INVITE_CODE:-"(not set, using existing)"}${NC}
 MAX_PLAYERS:         ${INFO}${MAX_PLAYERS:-"(not set, using existing)"}${NC}
 SERVER_PASSWORD:     $(if [[ -n "${SERVER_PASSWORD}" ]]; then echo -e "${HILITE}SET${NC}"; else echo -e "${INFO}NOT SET${NC}"; fi)
 GAME_PORT:           ${INFO}${GAME_PORT}${NC}

EOF
)
echo -e "${settings}"

### FUNCTIONS ###

term_handler() {
    echo -e "${INFO}Shutting down ${GAMENAME} server...${NC}"
    local PID
    PID=$(pgrep -f "WindroseServer-Win64-Shipping.exe" | head -1)
    if [[ -z "${PID}" ]]; then
        echo -e "${WARN}Could not find ${GAMENAME} server PID. Assuming dead...${NC}"
    else
        kill -TERM "${PID}"
        local timeout=30
        while kill -0 "${PID}" 2>/dev/null && [[ ${timeout} -gt 0 ]]; do
            sleep 1
            (( timeout-- ))
        done
        if kill -0 "${PID}" 2>/dev/null; then
            echo -e "${WARN}Server did not stop gracefully, forcing...${NC}"
            kill -9 "${PID}" 2>/dev/null
        fi
    fi
    wineserver -k 2>/dev/null || true
    sleep 1
    copy_files_to_data
    echo -e "${INFO}Shutdown complete.${NC}"
    exit 0
}

trap 'term_handler' SIGTERM

install_server() {
    echo -e "${INFO}-> Installing / updating ${GAMENAME} server files...${NC}"
    gosu steam:steam /depotdownloader/DepotDownloader \
        -app ${APPID} \
        -dir "${SERVERHOME}" \
        -validate
}

copy_files_to_data() {
    echo -e "${INFO}Saving game data to data volume...${NC}"
    for dir in "${SAVEDFOLDERS[@]}"; do
        if [[ -d "${SERVERHOME}/${GAMEBASEDIR}/${dir}" ]]; then
            mkdir -p "${GAMEDATA}/${dir}"
            cp -a "${SERVERHOME}/${GAMEBASEDIR}/${dir}/." "${GAMEDATA}/${dir}/"
        fi
    done
    if [[ -f "${SERVERHOME}/${GAMEBASE}/ServerDescription.json" ]]; then
        cp "${SERVERHOME}/${GAMEBASE}/ServerDescription.json" "${GAMEDATA}/ServerDescription.json"
    fi
    chown -R steam:steam "${GAMEDATA}"
}

copy_files_to_server() {
    echo -e "${INFO}Restoring game data from data volume...${NC}"
    for dir in "${SAVEDFOLDERS[@]}"; do
        if [[ -d "${GAMEDATA}/${dir}" ]]; then
            mkdir -p "${SERVERHOME}/${GAMEBASEDIR}/${dir}"
            cp -a "${GAMEDATA}/${dir}/." "${SERVERHOME}/${GAMEBASEDIR}/${dir}/"
        fi
    done
    if [[ -f "${GAMEDATA}/ServerDescription.json" ]]; then
        mkdir -p "${SERVERHOME}/${GAMEBASE}"
        cp "${GAMEDATA}/ServerDescription.json" "${SERVERHOME}/${GAMEBASE}/ServerDescription.json"
    fi
    chown -R steam:steam "${SERVERHOME}"
}

remove_server_files() {
    echo -e "${INFO}Removing server files from ${SERVERHOME}...${NC}"
    if [[ -d "${SERVERHOME}/${GAMEBASE}" ]]; then
        rm -rf "${SERVERHOME:?}"/*
        echo -e "${OK}Server files removed.${NC}"
    else
        echo -e "${ERR}Did not remove server files. Please manually empty the directory.${NC}"
    fi
}

patch_server_description() {
    local json_file="${SERVERHOME}/${GAMEBASE}/ServerDescription.json"
    if [[ ! -f "${json_file}" ]]; then
        echo -e "${WARN}ServerDescription.json not found, skipping patch.${NC}"
        return
    fi

    local tmp
    tmp=$(mktemp)
    cp "${json_file}" "${tmp}"

    [[ -n "${SERVER_NAME}" ]] && \
        jq --arg v "${SERVER_NAME}" \
            '.ServerDescription_Persistent.ServerName = $v' "${tmp}" > "${tmp}.new" && \
        mv "${tmp}.new" "${tmp}"

    [[ -n "${INVITE_CODE}" ]] && \
        jq --arg v "${INVITE_CODE}" \
            '.ServerDescription_Persistent.InviteCode = $v' "${tmp}" > "${tmp}.new" && \
        mv "${tmp}.new" "${tmp}"

    if [[ -n "${SERVER_PASSWORD}" ]]; then
        jq --arg v "${SERVER_PASSWORD}" \
            '.ServerDescription_Persistent.Password = $v | .ServerDescription_Persistent.IsPasswordProtected = true' \
            "${tmp}" > "${tmp}.new" && mv "${tmp}.new" "${tmp}"
    elif [[ "${IS_PASSWORD_PROTECTED}" == "false" ]]; then
        jq '.ServerDescription_Persistent.IsPasswordProtected = false | .ServerDescription_Persistent.Password = ""' \
            "${tmp}" > "${tmp}.new" && mv "${tmp}.new" "${tmp}"
    fi

    [[ -n "${MAX_PLAYERS}" ]] && \
        jq --argjson v "${MAX_PLAYERS}" \
            '.ServerDescription_Persistent.MaxPlayerCount = $v' "${tmp}" > "${tmp}.new" && \
        mv "${tmp}.new" "${tmp}"

    [[ -n "${USE_DIRECT_CONNECTION}" ]] && \
        jq --argjson v "${USE_DIRECT_CONNECTION}" \
            '.ServerDescription_Persistent.UseDirectConnection = $v' "${tmp}" > "${tmp}.new" && \
        mv "${tmp}.new" "${tmp}"

    [[ -n "${GAME_PORT}" ]] && \
        jq --argjson v "${GAME_PORT}" \
            '.ServerDescription_Persistent.DirectConnectionServerPort = $v' "${tmp}" > "${tmp}.new" && \
        mv "${tmp}.new" "${tmp}"

    [[ -n "${REGION}" ]] && \
        jq --arg v "${REGION}" \
            '.ServerDescription_Persistent.UserSelectedRegion = $v' "${tmp}" > "${tmp}.new" && \
        mv "${tmp}.new" "${tmp}"

    [[ -n "${P2P_PROXY_ADDRESS}" ]] && \
        jq --arg v "${P2P_PROXY_ADDRESS}" \
            '.ServerDescription_Persistent.P2pProxyAddress = $v' "${tmp}" > "${tmp}.new" && \
        mv "${tmp}.new" "${tmp}"

    cp "${tmp}" "${json_file}"
    rm -f "${tmp}" "${tmp}.new"
    chown steam:steam "${json_file}"
    echo -e "${OK}ServerDescription.json patched.${NC}"
}

### MAIN ###

firstrun=1
echo -e "${INFO}Starting ${GAMENAME} Dedicated Server...${NC}"

if [[ -f "${SERVERHOME}/${FIRSTRUNCHECKFILE}" ]]; then
    firstrun=0
fi

if [[ "${REMOVE_SERVER_FILES}" == "1" ]] && [[ ${firstrun} -eq 0 ]]; then
    echo -e "${WARN}Removing existing server files (REMOVE_SERVER_FILES=1)...${NC}"
    remove_server_files
    firstrun=1
fi

# Restore ServerDescription.json from data volume before download so it survives validate
if [[ ${firstrun} -eq 1 ]] && [[ -f "${GAMEDATA}/ServerDescription.json" ]]; then
    echo -e "${INFO}Restoring ServerDescription.json from data volume...${NC}"
    mkdir -p "${SERVERHOME}/${GAMEBASE}"
    cp "${GAMEDATA}/ServerDescription.json" "${SERVERHOME}/${GAMEBASE}/ServerDescription.json"
    chown -R steam:steam "${SERVERHOME}/${GAMEBASE}"
fi

if [[ "${SKIP_UPDATE}" == "0" ]] || [[ ! -f "${SERVERHOME}/${BINARY}" ]]; then
    if [[ ! -f "${SERVERHOME}/${BINARY}" ]]; then
        attempt=1
        until [[ -f "${SERVERHOME}/${BINARY}" ]]; do
            echo -e "${HILITE}Attempt #${attempt} to install server files...${NC}"
            install_server
            (( attempt++ ))
        done
    else
        install_server
    fi
fi

# First run with no existing config: copy template
if [[ ! -f "${SERVERHOME}/${GAMEBASE}/ServerDescription.json" ]]; then
    echo -e "${HILITE}No ServerDescription.json found — copying template. Edit INVITE_CODE and SERVER_NAME.${NC}"
    mkdir -p "${SERVERHOME}/${GAMEBASE}"
    cp /ServerDescription.json "${SERVERHOME}/${GAMEBASE}/ServerDescription.json"
    chown steam:steam "${SERVERHOME}/${GAMEBASE}/ServerDescription.json"
fi

patch_server_description
copy_files_to_server

# Wine prefix in data volume — persistent, initialized once
export WINEPREFIX="${GAMEDATA}/.wine"
export WINEARCH=win64
export WINEDLLOVERRIDES="mscoree,mshtml="
export WINEDEBUG=-all

if [[ ! -d "${WINEPREFIX}" ]]; then
    echo -e "${INFO}Initializing Wine prefix (first run — this may take a moment)...${NC}"
    Xvfb :99 -screen 0 1024x768x16 -nolisten tcp &
    XVFB_PID=$!
    DISPLAY=:99 gosu steam:steam wineboot --init >/dev/null 2>&1
    kill "${XVFB_PID}" 2>/dev/null || true
    chown -R steam:steam "${WINEPREFIX}"
    echo -e "${OK}Wine prefix initialized.${NC}"
fi

echo -e "${INFO}Launching ${GAMENAME} Dedicated Server...${NC}"
gosu steam:steam xvfb-run --auto-servernum \
    wine "${SERVERHOME}/${BINARY}" -log -port="${GAME_PORT}" &
ServerPID=$!
wait ${ServerPID}

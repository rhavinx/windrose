# Windrose Dedicated Server (Docker)

## Description
Docker container for hosting a dedicated server for [Windrose](https://store.steampowered.com/app/3041230/Windrose/). The game server is a Windows binary and runs under Wine.

Server files are downloaded via [DepotDownloader](https://github.com/SteamRE/DepotDownloader) using an anonymous Steam login — no Steam account or credentials required.

## Container data life cycle

Initial container start → "data" volume is empty, new files are created in live "server" volume.

:Loop  
Container shutdown → Live data is copied to the "data" volume.  
Container start (subsequent launches) → Files in "data" volume are copied to live "server" volume (overwriting existing). Environment variables are then applied on top.  
Goto Loop

If you modify files in the "server" volume directly, they will be overwritten the next time the server starts.

## Directory Structure
```
.
├── data                          # Volume bind mount
│   ├── .wine                     # Wine prefix (initialized on first run, persistent)
│   ├── Config                    # Synced with server folder on container start / shutdown
│   ├── Logs                      # Synced with server folder on container start / shutdown
│   ├── SaveProfiles              # Synced with server folder on container start / shutdown
│   └── ServerDescription.json   # Synced with server folder on container start / shutdown
└── server                        # Volume bind mount, populated via DepotDownloader
    ├── Engine
    ├── R5
    │   ├── Binaries
    │   │   └── Win64
    │   │       └── WindroseServer-Win64-Shipping.exe
    │   ├── Content
    │   │   └── Paks
    │   │       └── ~mods         # Place .pak mod files here
    │   ├── Saved                 # Contents synced with data folder on start / shutdown
    │   │   ├── Config
    │   │   ├── Logs
    │   │   └── SaveProfiles
    │   └── ServerDescription.json
    └── ...
```

## Quick Start (Docker)

1. Create a `docker-compose.yml` file from the example below.
2. Start the container: `docker compose up -d` and monitor with `docker compose logs -f`.
3. Forward port `7777` on your router for both **UDP and TCP**.
4. Connect via invite code or direct IP (see [Connection Methods](#connection-methods) below).

## Connection Methods

Windrose supports two connection methods, configured via `ServerDescription.json`. **They are mutually exclusive** — when Direct IP is active, invite codes will not work, and vice versa.

### Invite Code (default)
The default mode. Players connect via the in-game invite code. No additional router configuration is required beyond the standard port forward.

Set `USE_DIRECT_CONNECTION` to `false` (or leave it unset).

### Direct IP
Players connect by entering your public IP address directly in the game client. The invite code system is bypassed.

Set the following in your `docker-compose.yml`:
```yaml
USE_DIRECT_CONNECTION: "true"
DIRECT_CONNECTION_ADDRESS: "your.public.ip"
```

> **Note:** Direct IP requires both TCP and UDP port forwards. If you are on the same LAN as the server and connecting via your public IP, your router must support NAT loopback (hairpinning).

> **Known issue (game bug):** When using Direct IP, if you enter an incorrect password or there is a version mismatch, the game returns you to the main menu without displaying an error message.

## Mods

This container supports `.pak` mods only. Mods that require UE4SS (Unreal Engine Script System) — such as those shipped as Lua scripts or DLLs — are not supported.

Place `.pak` mod files in the `~mods` directory inside the server volume:

```
/path/to/server/R5/Content/Paks/~mods/
```

DepotDownloader will not touch files in this directory during updates or validation.

## ServerDescription.json

On first run, if no `ServerDescription.json` exists in the data volume, a fresh template is copied. The file is patched with your environment variable settings on every container start.

> **Important:** Do not manually edit `ServerDescription.json` in the server volume — it will be overwritten on next start. Edit it in the data volume instead, then bring the container back up.

> **Critical:** Never change `PersistentServerId` or `WorldIslandId` after your first run. These identify your world. Changing them will effectively start a new server.

## REMOVE_SERVER_FILES

If DepotDownloader gets into a bad state or you want a clean reinstall:

- Set `REMOVE_SERVER_FILES: "1"` in your `docker-compose.yml` for **one** launch.
- Then set it back to `"0"`. Your saves and `ServerDescription.json` are preserved in the data volume and will be restored automatically.

## Docker Compose (docker-compose.yml)

### Environment variables

| Variable                    | Description | Default |
| :-------------------------- | :---------- | :-----: |
| TZ                          | Timezone | `"UTC"` |
| PUID                        | Numeric user ID | `"1000"` |
| PGID                        | Numeric group ID | `"1000"` |
| SKIP_UPDATE                 | Skip DepotDownloader validation on start (faster startup, no update check) | `"0"` |
| GAME_PORT                   | Game port (adjust port mapping if changed) | `"7777"` |
| SERVER_NAME                 | Server display name | *(existing value)* |
| INVITE_CODE                 | Invite code for lobby-based connections | *(existing value)* |
| SERVER_PASSWORD             | Join password (also sets `IsPasswordProtected = true`) | *(existing value)* |
| IS_PASSWORD_PROTECTED       | Set to `"false"` to explicitly disable password protection | *(existing value)* |
| MAX_PLAYERS                 | Maximum player count | *(existing value)* |
| USE_DIRECT_CONNECTION       | Enable Direct IP connection mode (`"true"`/`"false"`) | *(existing value)* |
| DIRECT_CONNECTION_ADDRESS   | Public IP address for Direct IP mode | *(existing value)* |
| REGION                      | Connectivity server region | *(existing value)* |
| P2P_PROXY_ADDRESS           | P2P proxy address | *(existing value)* |
| REMOVE_SERVER_FILES         | Wipe server files for a clean reinstall (set to `"1"` for one launch only) | `"0"` |

```yaml
services:
  windrose:
    image: rhavinx/windrose:latest
    container_name: windrose
    stop_grace_period: 30s
    environment:
      TZ: "UTC"
      # PUID: "1000"
      # PGID: "1000"
      SKIP_UPDATE: "0"
      SERVER_NAME: "My Windrose Server"
      INVITE_CODE: "changeme"
      SERVER_PASSWORD: "changeme"
      MAX_PLAYERS: "4"
      GAME_PORT: "7777"
      # USE_DIRECT_CONNECTION: "true"
      # DIRECT_CONNECTION_ADDRESS: "your.public.ip"
      # REGION: ""
      # P2P_PROXY_ADDRESS: "127.0.0.1"
      # REMOVE_SERVER_FILES: "0"
    volumes:
      - /path/to/server:/home/steam/windrose/server
      - /path/to/data:/home/steam/windrose/data
    ports:
      - "7777:7777/udp"
      - "7777:7777/tcp"
    restart: unless-stopped
```

## Known Issues

- **R5Check warning in logs** (`Cannot save ServerDescription file`) — non-fatal. The game binary attempts to write back to `ServerDescription.json` at runtime and fails due to a Wine/filesystem interaction. The server continues running normally and all functionality is unaffected.
- **Slow first connection** — UE5 dedicated servers take time to preload the world. Subsequent connections are faster once the server is warm.
- **Direct IP silent failure** — see the known issue note under [Direct IP](#direct-ip) above.

## Changelog

* 12 May 2026:
  - Initial release
  - debian:trixie-slim + WineHQ stable + DepotDownloader (self-contained, no .NET install required)
  - Two-volume layout: server binaries + persistent data
  - Invite code and Direct IP connection modes supported
  - Environment variable patching of ServerDescription.json on every start

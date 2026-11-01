# Deploy WildWestPartyOnline

Target architecture:

- Cloudflare Pages: Godot Web client
- Koyeb: authoritative Godot dedicated WebSocket server

Gameplay rules, roles, cards and hidden information remain authoritative on the Koyeb server.

## 1. Local dedicated server

From the project root:

```powershell
godot --headless --path . server/DedicatedServer.tscn -- --development --port=7000
```

Local browser/client URL:

```text
ws://127.0.0.1:7000
```

`--development` is local testing only. Do not use it on Koyeb.

## 2. Docker local test

Build:

```powershell
docker build -t wwpo-server .
```

Run:

```powershell
docker run --rm -e PORT=7000 -p 7000:7000 wwpo-server
```

Expected log:

```text
ROOM SERVER READY ws://0.0.0.0:7000 development=false
```

## 3. Koyeb

Create a Web Service from the GitHub repository.

Recommended settings:

- Builder: Docker
- Dockerfile: `Dockerfile`
- Instance: Free while testing
- Exposed port: `7000`
- Protocol/route: HTTP/WebSocket public route to port 7000
- Health check: TCP on port 7000
- Scaling: one instance only

The server is stateful and stores rooms in memory. Do not scale to multiple server instances unless shared room/session storage is implemented.

Koyeb terminates public TLS. The Godot process itself listens internally on plain WebSocket/TCP. Players connect through the public `wss://...koyeb.app` endpoint.

The container reads Koyeb's `PORT` environment variable. The server defaults to `0.0.0.0` in dedicated mode.

Do not set `--development` in production.

## 4. Set the production WebSocket URL

After Koyeb reports the service as Healthy, copy the service hostname, for example:

```text
my-wild-west-server.koyeb.app
```

Edit:

```text
web/network-config.js
```

Replace:

```text
wss://REPLACE-ME.koyeb.app
```

with:

```text
wss://my-wild-west-server.koyeb.app
```

Do not add a trailing `/ws` unless you intentionally configure such a route/proxy.

## 5. Export the Godot Web client

The existing Web export preset loads `network-config.js`.

Export the Web build to:

```text
build/web/index.html
```

Confirm the resulting `build/web` also contains/copies `network-config.js` as expected by the export pipeline.

For an HTTPS public site, the server URL must be `wss://`, not `ws://`.

## 6. Cloudflare Pages

Deploy the contents of:

```text
build/web
```

as the static site.

Before uploading, check the sizes of the generated `.wasm` and `.pck` files. Cloudflare Pages has per-file limits; if a Godot output exceeds the current limit, use another static host or change the packaging strategy.

## 7. Production verification

Open two separate browser profiles/devices.

Browser A:
1. Enter player name.
2. Create room.
3. Copy room code.

Browser B:
1. Enter another name.
2. Join with the room code.

Then verify:

- lobby membership
- ready state
- private two-character selection
- only confirmed character becomes public
- hidden roles/hands remain private
- Sheriff starts
- BANG/reactions work
- reconnect keeps the same player/session
- game over works
- rematch reshuffles roles/characters/deck

For a real rules test, use 4–7 players. Two-player mode is debug-only.

## 8. Important production limitations

Rooms and sessions are stored in server memory.

Therefore:

- a Koyeb restart deletes active rooms
- scaling to multiple independent instances will break room affinity/state
- free-instance sleep/restart can interrupt active rooms
- one instance is the correct setup for the current architecture

Do not log session tokens, hidden roles, private hands or deck order.

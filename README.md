# UNSW Putt Party

3D mini-golf on the UNSW Kensington campus. Solo play runs locally. Multiplayer uses a WebSocket lobby on the Node server: create or join a room, then putt together with ghost balls for the other players.

## Versions

| Tool   | Version    |
|--------|------------|
| Godot  | **4.7.1**  |
| Node   | **22.19.0** |

## Test the server

From `server/`:

```bash
npm install
npm test
```

That runs the room logic tests and a live WebSocket protocol check (create, join, course vote, ball sync, bad join code). You do not need Godot for this. `npm test` starts its own server on a temporary port, so it is fine to leave `npm run dev` running at the same time.

Then start the real server:

```bash
npm run dev
```

Health check (expect `{"status":"ok",...}`):

```bash
curl http://127.0.0.1:8080/health
```

### Two-player test in Godot

1. Keep `npm run dev` running in `server/`.
2. Open `client/project.godot` in Godot 4.7.1.
3. **Debug > Run Multiple Instances > Run 2 Instances**, then press Play. Two game windows open.
4. In each window, set a name under Settings if you want, then choose **Multiplayer**.
5. Window A: **Create Lobby** (public). Note the 4-letter code.
6. Window B: the lobby should appear in the public list (**Join**), or use **Join With Code**.
7. Host presses **Start Game**. Everyone opens course selection with a 30 second countdown. Pick (and switch) a hole; a badge on each course shows how many players chose it. Only the host can press **Quick Start** to skip the timer. When time is up or the host skips, the most-picked course loads. Each player sees the other as a tinted ghost ball.

If the public list stays on "Connecting...", the Node process is not running or Godot cannot reach `ws://127.0.0.1:8080`.

**Solo Play** on the title screen does not need the server.

## Play in the browser

The server hosts the WebSocket game and serves the Godot web export from `client/build`.

1. Install Godot 4.7.1 and the **Web** export templates (`Editor > Manage Export Templates > Download`).
2. Export the client:

   ```bash
   # From the Godot editor: Project > Export > Web > Export Project
   # Output: client/build/index.html
   ```

   Or:

   ```bash
   ./scripts/export-web.sh
   ```

3. Start the server (`cd server && npm run dev`).
4. Open [http://127.0.0.1:8080](http://127.0.0.1:8080). Two browser tabs work as two players.

## Deploy (public internet)

The same Node process serves the web game, WebSocket lobby, and HTTPS-friendly phone remote at `/remote`.

Set `PUTT_PUBLIC_URL` to the public site origin (no trailing slash), for example `https://putt.example.com`. Phone QR codes and pair links use that origin so the remote works on any Wi-Fi. On Railway or Fly, the server also picks up `RAILWAY_PUBLIC_DOMAIN` or `FLY_APP_NAME` when `PUTT_PUBLIC_URL` is unset.

### Build and run with Docker

```bash
./scripts/export-web.sh   # needs Godot 4.7.1 web export
docker build -t unsw-putt-party .
docker run --rm -p 8080:8080 \
  -e PUTT_PUBLIC_URL=https://your-host.example \
  unsw-putt-party
```

### Railway

Use branch **`version1.3/map-fixes`** (not `version1.1/phone-remote`). That branch has the Dockerfile, `railway.toml`, and the Godot web export in `client/build`.

**From the Railway dashboard (GitHub connected):**

1. New project → Deploy from GitHub → `devsoc-unsw/trainee-bleach-26t2`.
2. Set the deploy branch to `version1.3/map-fixes`.
3. After the first deploy, open the service → Settings → Networking → **Generate domain**.
4. Set variable `PUTT_PUBLIC_URL` to that HTTPS origin (for example `https://YOUR_APP.up.railway.app`). Redeploy if phone QR codes still show a LAN address.

**From the CLI:**

```bash
railway login
railway up -y
railway domain
railway variable set PUTT_PUBLIC_URL=https://YOUR_APP.up.railway.app
```

`railway.toml` builds with the repo `Dockerfile`. The server also reads `RAILWAY_PUBLIC_DOMAIN` when `PUTT_PUBLIC_URL` is unset.

### Fly.io

```bash
# after fly auth login
fly launch --copy-config --no-deploy
fly secrets set PUTT_PUBLIC_URL=https://unsw-putt-party.fly.dev
fly deploy
```

### Temporary public tunnel (local machine)

Export the web build first (`./scripts/export-web.sh`), start the server on 8080, then open a quick tunnel:

```bash
./scripts/public-tunnel.sh
```

Copy the printed `https://....trycloudflare.com` origin and restart the server with it so phone QR codes match:

```bash
cd server
PUTT_PUBLIC_URL=https://YOUR-SUBDOMAIN.trycloudflare.com \
NODE_ENV=production PUTT_SKIP_HOST_PROBE=1 npm run start
```

Open that HTTPS origin in a browser for the game. Phone remotes use `/remote?c=CODE` on the same host from any network.

Desktop Godot clients can join with:

```bash
PUTT_SERVER=wss://YOUR-SUBDOMAIN.trycloudflare.com
```

Quick tunnels are temporary. Prefer Railway or Fly for a lasting public host.

## Server scripts

| Script  | Command           | Description                          |
|---------|-------------------|--------------------------------------|
| `dev`   | `npm run dev`     | Watch mode with tsx, port 8080       |
| `test`  | `npm test`        | Room + WebSocket protocol tests      |
| `build` | `npm run build`   | Compile TypeScript to `dist/`        |
| `start` | `npm run start`   | Run compiled JS                      |

Desktop Godot clients connect to `ws://127.0.0.1:8080` unless `PUTT_SERVER` is set.

## Phone remote

### Local desktop (same Wi-Fi)

1. In Godot, open a hole (solo or multiplayer).
2. Gear, then **LINK PHONE**. Scan the QR, or type the phone address shown under it.
3. Use the **https** address when you need motion sensors.
4. Aim with the AIM pad. Swing the phone up, then down.

### Deployed / browser / any Wi-Fi

Online and web builds open a per-player code on the shared server. Scan the QR to open `https://YOUR_HOST/remote?c=CODE`. Pose and swings go over the same WebSocket host as the game, so the phone does not need your LAN.

Each player has their own code and their own ball.

## Running the Godot editor

1. Install Godot 4.7.1
2. Open `client/project.godot`
3. Press play (title screen). Solo works offline; Multiplayer needs `npm run dev` in `server/`.

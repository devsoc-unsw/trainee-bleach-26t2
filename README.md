# UNSW Putt Party

3D multiplayer mini-golf game. Up to 6 players putt simultaneously through a six-hole course modelled on UNSW Kensington campus.

## Versions

| Tool   | Version    |
|--------|------------|
| Godot  | **4.7.1**  |
| Node   | **22.19.0** |

## Running the Server

```bash
cd server
npm install
npm run dev
```

Server starts on `http://127.0.0.1:8080`

### Scripts

| Script  | Command           | Description                   |
|---------|-------------------|-------------------------------|
| `dev`   | `npm run dev`     | Watch mode with tsx           |
| `build` | `npm run build`   | Compile TypeScript to `dist/` |
| `start` | `npm run start`   | Run compiled JS               |

### Health check

```bash
curl http://localhost:8080/health
```

## Running the Client

1. Install Godot 4.7.1
2. Install web export templates (Editor > Manage Export Templates > Download)
3. Open `client/project.godot`
4. Press play or export to web (Project > Export > Web)

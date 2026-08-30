
import type { WebSocket } from 'ws';
import { GameState, Room, Player } from './interface.js';

const CODE_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ123456789';
const TIMEOUT_MS = 30 * 60 * 1000;

// room management

const rooms = new Map<string, Room>();

export function createRoom(): Room {
  const code = generateRoomCode(new Set(rooms.keys()));
  const room: Room = {
    code: code,
    players: new Map(),
    hostId: null,
    state: GameState.LOBBY,
    holes: [],
    currentHoleIndex: 0,
    createdAt: Date.now(),
    lastModified: Date.now(),
  };
  rooms.set(code, room);
  return room;
}

export function getRoom(code: string): Room | undefined {
  return rooms.get(code);
}

export function deleteRoom(code: string): void {
  rooms.delete(code);
}

// need to call this periodically
export function deleteIdleRoom(): void {
  const now = Date.now();
  for (const [code, room] of rooms) {
    if (now - room.lastModified >= TIMEOUT_MS) {
      deleteRoom(code);
    }
  }
}



// Player management

export function addPlayer(room: Room, ws: WebSocket, name: string): Player {
  const player: Player = {
    id: generatePlayerId(),
    ws: ws,
    name: name,
    ready: false,
    isHost: room.players.size === 0,
    pos: [0, 0, 0],
    vel: [0, 0, 0],
    atRest: true,
    strokes: 0,
    holedThisHole: false,
    lastShotAt: 0,
    holeResults: [],
  };
  
  if (player.isHost) {
    room.hostId = player.id;
  }
  
  room.players.set(player.id, player);
  updateRoomLastModified(room);

  return player;
}

export function removePlayer(room: Room, playerId: string): void {
  room.players.delete(playerId);

  // reassign host if the host left and players remain
  if (room.hostId === playerId) {
    const next = room.players.values().next().value as Player | undefined;
    if (next) {
        room.hostId = next.id;
        next.isHost = true;
    }
  }
  updateRoomLastModified(room);
  if (room.players.size === 0) {
    deleteRoom(room.code);
  }
}

export function updatePlayerScore(room: Room, playerId: string) {
  const player = room.players.get(playerId);
  if (!player) {
    return null;
  }

  player.strokes += 1;
  player.lastShotAt = Date.now();
  updateRoomLastModified(room);

  return player.strokes;
}



// helpers:

function updateRoomLastModified(room: Room): void {
  room.lastModified = Date.now();
}

export function generateRoomCode(existingCodes: Set<string>): string {
  let code: string;
  do {
    code = '';
    for (let i = 0; i < 4; i++) {
      code += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
    }
  } while (existingCodes.has(code));
  return code;
}

function generatePlayerId(): string {
  return Math.random().toString(36).slice(2, 10);
}

// Broadcast helpers

export function sendTo(player: Player, msg: unknown): void {
  if (player.ws.readyState === player.ws.OPEN) {
    player.ws.send(JSON.stringify(msg));
  }
}

export function broadcast(room: Room, msg: unknown, exceptId?: string): void {
  for (const player of room.players.values()) {
    if (player.id !== exceptId) sendTo(player, msg);
  }
}

export function lobbySnapshot(room: Room) {
  return [...room.players.values()].map((p) => ({
    player_id: p.id,
    name: p.name,
    colour: p.colour,
    ready: p.ready,
  }));
}

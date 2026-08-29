
import type { WebSocket } from 'ws';

const CODE_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ123456789';

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

// types

export enum GameState {
  LOBBY = 'LOBBY',
  COUNTDOWN = 'COUNTDOWN',
  HOLE_ACTIVE = 'HOLE_ACTIVE',
  HOLE_SUMMARY = 'HOLE_SUMMARY',
  MATCH_END = 'MATCH_END',
}

export interface Vec3 {
  x: number;
  y: number;
  z: number;
}

export interface Player {
  id: string;
  ws: WebSocket;
  name: string;
  ready: boolean;
  isHost: boolean;

  // ball management
  pos: Vec3;
  vel: Vec3;
  atRest: boolean;
  strokes: number;
  holedThisHole: boolean;
  lastShotAt: number;
}

export interface HoleDetails {
  index: number;
  par: number;
  spawn: Vec3;
  cup: Vec3;
  cupTolerance: number;
}

export interface Room {
  code: string;
  players: Map<string, Player>;
  hostId: string | null;
  state: GameState;
  holes: HoleDetails[];
  currentHoleIndex: number;
  createdAt: number;
  lastModified: number;
}

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


// Player management

export function addPlayer(room: Room, ws: WebSocket, name: string): Player {
  const player: Player = {
    id: generatePlayerId(),
    ws,
    name,
    ready: false,
    isHost: room.players.size === 0,
    pos: { x: 0, y: 0, z: 0 },
    vel: { x: 0, y: 0, z: 0 },
    atRest: true,
    strokes: 0,
    holedThisHole: false,
    lastShotAt: 0,
  };

  if (player.isHost) {
    room.hostId = player.id;
  }

  room.players.set(player.id, player);
  // TODO: room last modified now
  return player;
}

export function removePlayer(room: Room, playerId: string): void {
  room.players.delete(playerId);

  // reassign host if the host left and players remain
  if (room.hostId === playerId) {
    const next = room.players.values().next().value as Player | undefined;

    room.hostId = null;
    if (next) {
        room.hostId = next.id;
        next.isHost = true;
    }
  }

  // TODO: room last modified now

  if (room.players.size === 0) {
    deleteRoom(room.code);
  }
}


// when and where is this called?
export function deleteIdleRoom() {
  // loop through all active rooms
  // check the last time modified, compare it with the time now
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
    ready: p.ready,
  }));
}

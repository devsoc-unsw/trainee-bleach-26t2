import type { WebSocket } from 'ws';

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

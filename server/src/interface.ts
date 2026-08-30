import type { WebSocket } from 'ws';

export enum GameState {
  LOBBY = 'LOBBY',
  COUNTDOWN = 'COUNTDOWN',
  HOLE_ACTIVE = 'HOLE_ACTIVE',
  HOLE_SUMMARY = 'HOLE_SUMMARY',
  MATCH_END = 'MATCH_END',
}

type Vec3 = [number, number, number]

export interface Player {
  id: string;
  ws: WebSocket;
  name: string;
  colour: string;
  ready: boolean;
  isHost: boolean;

  // ball management
  pos: Vec3;
  vel: Vec3;
  atRest: boolean;

  // curr hole stat tracking
  strokes: number;
  holedThisHole: boolean;
  lastShotAt: number;

  holeResults: HoleResult[];
}

export interface HoleConfig {
  index: number;
  par: number;
  spawn: Vec3;
  cup: Vec3;
  cupTolerance: number;
}

export interface HoleResult {
  holeIndex: number;
  strokes: number;
  par: number;
}

export interface Room {
  code: string;
  players: Map<string, Player>;
  hostId: string | null;
  state: GameState;
  holes: HoleConfig[];
  currentHoleIndex: number;
  createdAt: number;
  lastModified: number;
  availableColours: string[];
}

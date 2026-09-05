import { z } from 'zod';

export const envelopeSchema = z
  .object({
    t: z.string().min(1, 'Message type "t" must be a non-empty string'),
  })
  .passthrough();

export type Envelope = z.infer<typeof envelopeSchema>;

export interface ErrorResponse {
  t: 'error';
  code: string;
  message: string;
}

export interface PlayerPublic {
  id: string;
  name: string;
  color: string;
  host: boolean;
  strokes: number;
  holed: boolean;
  joinedAt: number;
}

export interface RoomPublic {
  code: string;
  name: string;
  isPublic: boolean;
  players: number;
  maxPlayers: number;
  host: string;
}

export interface LobbyStateMessage {
  t: 'lobby_state';
  code: string;
  name: string;
  isPublic: boolean;
  hostId: string;
  mapId: string;
  maxPlayers: number;
  rounds: number;
  roundIndex: number;
  players: PlayerPublic[];
}

export interface LobbyListMessage {
  t: 'lobby_list';
  rooms: RoomPublic[];
}

export interface WelcomeMessage {
  t: 'welcome';
  playerId: string;
}

export interface MatchStartMessage {
  t: 'match_start';
  mapId: string;
}

export interface BallSnap {
  id: string;
  x: number;
  y: number;
  z: number;
  vx: number;
  vy: number;
  vz: number;
  atRest: boolean;
}

export interface SnapshotMessage {
  t: 'snapshot';
  balls: BallSnap[];
}

export interface StrokeUpdateMessage {
  t: 'stroke_update';
  playerId: string;
  strokes: number;
}

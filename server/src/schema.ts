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

// HELPER SCHEMAS:

const vec2Schema = z
.object({
  x: z.number(),
  y: z.number(),
});

const vec3Schema = z
.object({
  x: z.number(),
  y: z.number(),
  z: z.number(),
});

const lobbyPlayerSchema = z
.object({
  player_id: z.string(),
  name: z.string(),
  ready: z.boolean(),
});

const snapshotBallSchema = z
.object({
  player_id: z.string(),
  pos: vec3Schema,
  vel: vec3Schema,
  at_rest: z.boolean(),
});

const holeResultSchema = z
.object({
  player_id: z.string(),
  strokes: z.number().int().min(0),
});

const placingSchema = z
.object({
  player_id: z.string(),
  total_strokes: z.number().int().min(0),
  rank: z.number().int().min(1),
});

// TODO: add per-message schemas for client -> server:
// player wants join the room
export const joinSchema = z
  .object({
    t: z.literal('join'),
    name: z.string().min(1).max(24),
    code: z.string().length(4).optional(),
});

export type JoinMessage = z.infer<typeof joinSchema>;

// game room is ready to start the game
export const readySchema = z
.object({
  t: z.literal('ready'),
});
export type ReadyMessage = z.infer<typeof readySchema>;


// started the match
export const startMatchSchema = z
.object({
  t: z.literal('start_match'),
});
export type StartMatchMessage = z.infer<typeof startMatchSchema>;

// send a shot
export const shotSchema = z
.object({
  t: z.literal('shot'),
  dir: vec2Schema,
  power: z.number().min(0).max(1),
});
export type ShotMessage = z.infer<typeof shotSchema>;

// send ball state
export const ballStateSchema = z
.object({
  t: z.literal('ball_state'),
  pos: vec3Schema,
  vel: vec3Schema,
  at_rest: z.boolean(),
});
export type BallStateMessage = z.infer<typeof ballStateSchema>;

// holed
export const holedSchema = z
.object({
  t: z.literal('holed'),
  pos: vec3Schema,
});
export type HoledMessage = z.infer<typeof holedSchema>;

// oob
export const oobSchema = z
.object({
  t: z.literal('oob'),
});
export type OobMessage = z.infer<typeof oobSchema>;


export const pingSchema = z.object({
  t: z.literal('ping'),
});
export type PingMessage = z.infer<typeof pingSchema>;


export const clientMessageSchema = z.discriminatedUnion('t', [
  joinSchema,
  readySchema,
  shotSchema,
  startMatchSchema,
  ballStateSchema,
  holedSchema,
  oobSchema,
  pingSchema,
]);
export type ClientMessage = z.infer<typeof clientMessageSchema>;


// TODO: add per-message schemas for server -> client:

export const joinedSchema = z
.object({
  t: z.literal('joined'),
  player_id: z.string(),
  code: z.string(),
});
export type JoinedMessage = z.infer<typeof joinedSchema>;


export const playerJoinedSchema = z
.object({
  t: z.literal('player_joined'),
  player: lobbyPlayerSchema,
});
export type PlayerJoinedMessage = z.infer<typeof playerJoinedSchema>;


export const playerLeftSchema = z
.object({
  t: z.literal('player_left'),
  player_id: z.string(),
});
export type PlayerLeftMessage = z.infer<typeof playerLeftSchema>;


export const lobbyStateSchema = z
.object({
  t: z.literal('lobby_state'),
  players: z.array(lobbyPlayerSchema),
});  
export type LobbyStateMessage = z.infer<typeof lobbyStateSchema>;


export const matchStartedSchema = z
.object({
  t: z.literal('match_started'),
  holes: z.array(z.string()),
});
export type MatchStartedMessage = z.infer<typeof matchStartedSchema>;


export const holeStartedSchema = z
.object({
  t: z.literal('hole_started'),
  hole_index: z.number().int().min(0),
  par: z.number().int().min(1),
  spawn: vec3Schema,
});
export type HoleStartedMessage = z.infer<typeof holeStartedSchema>;


export const snapshotSchema = z
.object({
  t: z.literal('snapshot'),
  balls: z.array(snapshotBallSchema),
});
export type SnapshotMessage = z.infer<typeof snapshotSchema>;


export const strokeUpdateSchema = z
.object({
  t: z.literal('stroke_update'),
  player_id: z.string(),
  strokes: z.number().int().min(0),
});
export type StrokeUpdateMessage = z.infer<typeof strokeUpdateSchema>;


export const holeEndedSchema = z
.object({
  t: z.literal('hole_ended'),
  results: z.array(holeResultSchema),
});
export type HoleEndedMessage = z.infer<typeof holeEndedSchema>;


export const matchEndedSchema = z
.object({
  t: z.literal('match_ended'),
  placings: z.array(placingSchema),
});
export type MatchEndedMessage = z.infer<typeof matchEndedSchema>;


export const pongSchema = z
.object({
  t: z.literal('pong'),
});
export type PongMessage = z.infer<typeof pongSchema>;

export const serverMessageSchema = z.discriminatedUnion('t', [
  joinedSchema,
  lobbyStateSchema,
  playerJoinedSchema,
  playerLeftSchema,
  matchStartedSchema,
  holeStartedSchema,
  snapshotSchema,
  strokeUpdateSchema,
  holeEndedSchema,
  matchEndedSchema,
  pongSchema,
]);
export type ServerMessage = z.infer<typeof serverMessageSchema>;
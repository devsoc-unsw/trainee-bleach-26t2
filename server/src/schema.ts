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
const vec2Schema = z.tuple([
  z.number(),
  z.number()
]);

const vec3Schema = z.tuple([
  z.number(),
  z.number(),
  z.number()
]);

const lobbyPlayerSchema = z
.object({
  id: z.string(),
  name: z.string(),
  colour: z.string(), // valid hex (?)
  ready: z.boolean(),
});

const snapshotBallSchema = z
.object({
  id: z.string(),
  pos: vec3Schema,
  vel: vec3Schema,
  atRest: z.boolean(),
  holed: z.boolean(),
});

const holeResultSchema = z
.object({
  playerId: z.string(),
  strokes: z.number().int().min(0),
  relToPar: z.number().int(),
});

const ongoingResultSchema = z
.object({
  playerId: z.string(),
  total: z.number().int().min(0),
  relToPar: z.number().int(),
});

const placingSchema = z
.object({
  playerId: z.string(),
  total: z.number().int().min(0),
  place: z.number().int().min(1),
});

const holeConfigSchema = z.object({
  index: z.number(),
  par: z.number().int().min(0),
  name: z.string(),
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
  atRest: z.boolean(),
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
// export const oobSchema = z
// .object({
//   t: z.literal('oob'),
// });
// export type OobMessage = z.infer<typeof oobSchema>;


export const pingSchema = z.object({
  t: z.literal('ping'),
  ts: z.number(),
});
export type PingMessage = z.infer<typeof pingSchema>;


export const clientMessageSchema = z.discriminatedUnion('t', [
  joinSchema,
  readySchema,
  shotSchema,
  startMatchSchema,
  ballStateSchema,
  holedSchema,
  pingSchema,
]);
export type ClientMessage = z.infer<typeof clientMessageSchema>;


// TODO: add per-message schemas for server -> client:

export const playerJoinedSchema = z
.object({
  t: z.literal('joined'),
  playerId: z.string(),
  code: z.string(),
  players: z.array(lobbyPlayerSchema),
});
export type PlayerJoinedMessage = z.infer<typeof playerJoinedSchema>;


export const lobbyStateSchema = z
.object({
  t: z.literal('lobby_state'),
  players: z.array(lobbyPlayerSchema),
});  
export type LobbyStateMessage = z.infer<typeof lobbyStateSchema>;


export const matchStartSchema = z
.object({
  t: z.literal('match_start'),
  courseId: z.string(),
  holes: z.array(holeConfigSchema),
});
export type MatchStartMessage = z.infer<typeof matchStartSchema>;


export const holeStartSchema = z
.object({
  t: z.literal('hole_start'),
  holeIndex: z.number().int().min(0),
  par: z.number().int().min(0),
  timerMs: z.number().min(0),
  spawn: vec3Schema,
});
export type HoleStartMessage = z.infer<typeof holeStartSchema>;


export const snapshotSchema = z
.object({
  t: z.literal('snapshot'),
  tick: z.number(),
  balls: z.array(snapshotBallSchema),
});
export type SnapshotMessage = z.infer<typeof snapshotSchema>;


export const strokeUpdateSchema = z
.object({
  t: z.literal('stroke_update'),
  playerId: z.string(),
  holeIndex: z.number(), 
  strokes: z.number().int().min(0),
});
export type StrokeUpdateMessage = z.infer<typeof strokeUpdateSchema>;


export const holeEndSchema = z
.object({
  t: z.literal('hole_end'),
  holeIndex: z.number(),
  results: z.array(holeResultSchema),
});
export type HoleEndMessage = z.infer<typeof holeEndSchema>;


export const scoreUpdateSchema = z.object({
  t: z.literal('score_update'),
  totals: z.array(ongoingResultSchema),
});
export type ScoreUpdateMessage = z.infer<typeof scoreUpdateSchema>;


export const matchEndedSchema = z
.object({
  t: z.literal('match_end'),
  placings: z.array(placingSchema),
});
export type MatchEndedMessage = z.infer<typeof matchEndedSchema>;


export const playerLeftSchema = z
.object({
  t: z.literal('player_left'),
  playerId: z.string(),
});
export type PlayerLeftMessage = z.infer<typeof playerLeftSchema>;


export const errorSchema = z.object({
  t: z.literal('error'),
  code: z.string(),
  message: z.string(),
});


export const pongSchema = z
.object({
  t: z.literal('pong'),
  ts: z.number(),
});
export type PongMessage = z.infer<typeof pongSchema>;

export const serverMessageSchema = z.discriminatedUnion('t', [
  playerJoinedSchema,
  lobbyStateSchema,
  playerLeftSchema,
  matchStartSchema,
  holeStartSchema,
  scoreUpdateSchema,
  snapshotSchema,
  strokeUpdateSchema,
  holeEndSchema,
  matchEndedSchema,
  errorSchema,
  pongSchema,
]);
export type ServerMessage = z.infer<typeof serverMessageSchema>;
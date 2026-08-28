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

const vec2Schema = z.object({
  x: z.number(),
  y: z.number(),
});

const vec3Schema = z.object({
  x: z.number(),
  y: z.number(),
  z: z.number(),
});



// TODO: add per-message schemas for client -> server:
// player wants join the room
export const joinSchema = z
  .object({
    t: z.literal('join'),
    name: z.string().min(1).max(24),
    code: z.string().optional()
});

export type JoinMessage = z.infer<typeof joinSchema>;

// game room is ready to start the game
export const readySchema = z
.object({
  t: z.literal('ready')
});
export type ReadyMessage = z.infer<typeof readySchema>;


// start the match
export const startSchema = z
.object({
  t: z.literal('start')
});
export type StartMessage = z.infer<typeof startSchema>;

// send a shot
export const shotSchema = z
.object({
  t: z.literal('shot'),
  direction: vec2Schema,
  power: z.number()
});
export type shotMessage = z.infer<typeof shotSchema>;

// send ball state
export const ballStateSchema = z
.object({
  t: z.literal('ball'),
  pos: vec3Schema,
  vel: vec3Schema,
  rest: z.boolean()
});
export type ballMessage = z.infer<typeof ballStateSchema>;

// holed
export const holedSchema = z
.object({
  t: z.literal('holed'),
  pos: vec3Schema
});
export type holedMessage = z.infer<typeof holedSchema>;

// oob
export const oobSchema = z
.object({
  t: z.literal('oob')
});
export type oobMessage = z.infer<typeof oobSchema>;

export const clientMessageSchema = z.discriminatedUnion('t', [
  joinSchema,
  readySchema,
  shotSchema,
  ballStateSchema,
  holedSchema,
  oobSchema,
]);
export type ClientMessage = z.infer<typeof clientMessageSchema>;
// TODO: add per-message schemas for server -> client:


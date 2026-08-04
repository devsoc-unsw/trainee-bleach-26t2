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

// TODO: add per-message schemas for client -> server:

// TODO: add per-message schemas for server -> client:


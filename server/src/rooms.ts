import type { WebSocket } from 'ws';
import type {
  BallSnap,
  LobbyListMessage,
  LobbyStateMessage,
  PlayerPublic,
  RoomPublic,
} from './schema.js';

const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export const BALL_COLORS = [
  '#E23B3B',
  '#4CB8B0',
  '#F2D04B',
  '#7B5BBF',
  '#E67E22',
  '#27AE60',
  '#2980B9',
  '#E84393',
];
const COLORS = BALL_COLORS;
const MAX_PLAYERS = 4;
export const MAP_IDS = ['rainbow_stairs', 'main_walk', 'village_green'] as const;
export const VOTE_MS = 30_000;

export type Phase = 'lobby' | 'selecting' | 'playing';
export type MapId = (typeof MAP_IDS)[number];
export type GameMode = 'turn_by_turn' | 'free_for_all';
export const HOLE_SUMMARY_MS = 10_000;

export interface Player {
  id: string;
  name: string;
  color: string;
  host: boolean;
  ws: WebSocket;
  strokes: number;
  totalStrokes: number;
  holed: boolean;
  holeTime: number;
  totalTime: number;
  joinedAt: number;
  ball: BallSnap;
}

export interface Room {
  code: string;
  name: string;
  isPublic: boolean;
  hostId: string;
  mapId: string;
  phase: Phase;
  rounds: number;
  roundIndex: number;
  gameMode: GameMode;
  summaryPending: boolean;
  summaryPhase: 'hole' | 'standings' | '';
  holeStartedAt: number;
  joinSeq: number;
  players: Map<string, Player>;
  votes: Map<string, string>;
  voteDeadline: number;
  takenPickups: Map<string, number>;
}

const rooms = new Map<string, Room>();
const socketRoom = new Map<WebSocket, string>();
const socketIds = new WeakMap<WebSocket, string>();
const voteTimers = new Map<string, ReturnType<typeof setTimeout>>();
const holeAdvanceTimers = new Map<string, ReturnType<typeof setTimeout>>();
let playerSeq = 0;
let onVoteEnded: ((room: Room) => void) | undefined;

export function setVoteEndedHandler(handler: ((room: Room) => void) | undefined): void {
  onVoteEnded = handler;
}

export function resetForTests(): void {
  for (const timer of voteTimers.values()) {
    clearTimeout(timer);
  }
  voteTimers.clear();
  for (const timer of holeAdvanceTimers.values()) {
    clearTimeout(timer);
  }
  holeAdvanceTimers.clear();
  rooms.clear();
  socketRoom.clear();
  playerSeq = 0;
}

export function register(ws: WebSocket): string {
  const existing = socketIds.get(ws);
  if (existing) {
    return existing;
  }
  const id = `p${++playerSeq}`;
  socketIds.set(ws, id);
  return id;
}

export function publicRooms(): RoomPublic[] {
  const out: RoomPublic[] = [];
  for (const room of rooms.values()) {
    if (!room.isPublic || room.phase !== 'lobby') {
      continue;
    }
    const host = room.players.get(room.hostId);
    out.push({
      code: room.code,
      name: room.name,
      isPublic: true,
      players: room.players.size,
      maxPlayers: MAX_PLAYERS,
      host: host?.name ?? 'Host',
    });
  }
  return out;
}

export function lobbyList(): LobbyListMessage {
  return { t: 'lobby_list', rooms: publicRooms() };
}

export function lobbyState(room: Room): LobbyStateMessage {
  const players: PlayerPublic[] = [];
  for (const p of room.players.values()) {
    players.push({
      id: p.id,
      name: p.name,
      color: p.color,
      host: p.host,
      strokes: p.strokes,
      holed: p.holed,
      joinedAt: p.joinedAt,
    });
  }
  players.sort((a, b) => a.joinedAt - b.joinedAt);
  return {
    t: 'lobby_state',
    code: room.code,
    name: room.name,
    isPublic: room.isPublic,
    hostId: room.hostId,
    mapId: room.mapId,
    maxPlayers: MAX_PLAYERS,
    rounds: room.rounds,
    roundIndex: room.roundIndex,
    gameMode: room.gameMode,
    players,
  };
}

export function send(ws: WebSocket, payload: unknown): void {
  if (ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(payload));
  }
}

export function broadcast(room: Room, payload: unknown, except?: WebSocket): void {
  const raw = JSON.stringify(payload);
  for (const p of room.players.values()) {
    if (except && p.ws === except) {
      continue;
    }
    if (p.ws.readyState === p.ws.OPEN) {
      p.ws.send(raw);
    }
  }
}

function freshCode(): string {
  for (let attempt = 0; attempt < 24; attempt++) {
    let code = '';
    for (let i = 0; i < 4; i++) {
      code += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
    }
    if (!rooms.has(code)) {
      return code;
    }
  }
  return `P${String(Date.now()).slice(-3)}`;
}

function nextColor(room: Room): string {
  const used = new Set(
    Array.from(room.players.values()).map((p) => p.color.trim().toUpperCase())
  );
  return COLORS.find((c) => !used.has(c.toUpperCase())) ?? COLORS[0] ?? '#E23B3B';
}

function attachSocket(ws: WebSocket, code: string): void {
  const previous = socketRoom.get(ws);
  if (previous && previous !== code) {
    leave(ws);
  }
  socketRoom.set(ws, code);
}

export function roomFor(ws: WebSocket): Room | undefined {
  const code = socketRoom.get(ws);
  if (!code) {
    return undefined;
  }
  return rooms.get(code);
}

export function createRoom(
  ws: WebSocket,
  name: string,
  isPublic: boolean,
  playerName: string,
  rounds = 1,
  gameMode: string = 'turn_by_turn'
): Room {
  leave(ws);
  const code = freshCode();
  const id = register(ws);
  const room: Room = {
    code,
    name: name.slice(0, 32) || 'Putt Party',
    isPublic,
    hostId: id,
    mapId: '',
    phase: 'lobby',
    rounds: clampRounds(rounds),
    roundIndex: 0,
    gameMode: normalizeGameMode(gameMode),
    summaryPending: false,
    summaryPhase: '',
    holeStartedAt: 0,
    joinSeq: 0,
    players: new Map(),
    votes: new Map(),
    voteDeadline: 0,
    takenPickups: new Map(),
  };
  const player: Player = {
    id,
    name: playerName.slice(0, 18) || 'Player',
    color: COLORS[0] ?? '#E23B3B',
    host: true,
    ws,
    strokes: 0,
    totalStrokes: 0,
    holed: false,
    holeTime: 0,
    totalTime: 0,
    joinedAt: ++room.joinSeq,
    ball: emptyBall(id),
  };
  room.players.set(id, player);
  rooms.set(code, room);
  attachSocket(ws, code);
  return room;
}

export function joinRoom(ws: WebSocket, code: string, playerName: string): Room | string {
  const room = rooms.get(code.toUpperCase());
  if (!room) {
    return 'No lobby with that code';
  }
  if (room.phase !== 'lobby') {
    return 'That game already started';
  }
  if (room.players.size >= MAX_PLAYERS) {
    return 'That lobby is full';
  }
  leave(ws);
  const id = register(ws);
  const player: Player = {
    id,
    name: playerName.slice(0, 18) || 'Player',
    color: nextColor(room),
    host: false,
    ws,
    strokes: 0,
    totalStrokes: 0,
    holed: false,
    holeTime: 0,
    totalTime: 0,
    joinedAt: ++room.joinSeq,
    ball: emptyBall(id),
  };
  room.players.set(id, player);
  attachSocket(ws, room.code);
  return room;
}

export function leave(ws: WebSocket): Room | undefined {
  const code = socketRoom.get(ws);
  socketRoom.delete(ws);
  if (!code) {
    return undefined;
  }
  const room = rooms.get(code);
  if (!room) {
    return undefined;
  }
  let leaving: Player | undefined;
  for (const p of room.players.values()) {
    if (p.ws === ws) {
      leaving = p;
      break;
    }
  }
  if (!leaving) {
    return room;
  }
  room.players.delete(leaving.id);
  room.votes.delete(leaving.id);
  if (room.players.size === 0) {
    clearVoteTimer(code);
    clearHoleAdvance(code);
    rooms.delete(code);
    return undefined;
  }
  if (room.hostId === leaving.id) {
    const next = newestPlayer(room);
    if (next) {
      room.hostId = next.id;
      next.host = true;
    }
  }
  return room;
}

export function playerFor(ws: WebSocket): Player | undefined {
  const room = roomFor(ws);
  if (!room) {
    return undefined;
  }
  for (const p of room.players.values()) {
    if (p.ws === ws) {
      return p;
    }
  }
  return undefined;
}

export function startMatch(ws: WebSocket, mapId: string): Room | string {
  const room = roomFor(ws);
  const player = playerFor(ws);
  if (!room || !player) {
    return 'You are not in a lobby';
  }
  if (player.id !== room.hostId) {
    return 'Only the host can start';
  }
  if (room.phase === 'playing') {
    return 'That game already started';
  }
  return commitMatch(room, normalizeMapId(mapId));
}

export function beginSelect(ws: WebSocket): Room | string {
  const room = roomFor(ws);
  const player = playerFor(ws);
  if (!room || !player) {
    return 'You are not in a lobby';
  }
  if (player.id !== room.hostId) {
    return 'Only the host can start';
  }
  if (room.phase === 'playing') {
    return 'That game already started';
  }
  if (room.phase === 'selecting') {
    return room;
  }
  if (room.phase === 'lobby') {
    room.roundIndex = 0;
    room.summaryPending = false;
    room.summaryPhase = '';
    for (const p of room.players.values()) {
      p.totalStrokes = 0;
      p.strokes = 0;
      p.holeTime = 0;
      p.totalTime = 0;
      p.holed = false;
    }
  }
  startVote(room);
  return room;
}

export function castVote(ws: WebSocket, mapId: string): Room | string {
  const room = roomFor(ws);
  const player = playerFor(ws);
  if (!room || !player) {
    return 'You are not in a lobby';
  }
  if (room.phase !== 'selecting') {
    return 'Course pick is not open';
  }
  const id = normalizeMapId(mapId);
  room.votes.set(player.id, id);
  return room;
}

export function quickStart(ws: WebSocket): Room | string {
  const room = roomFor(ws);
  const player = playerFor(ws);
  if (!room || !player) {
    return 'You are not in a lobby';
  }
  if (player.id !== room.hostId) {
    return 'Only the host can start';
  }
  if (room.phase !== 'selecting') {
    return 'Course pick is not open';
  }
  return commitMatch(room, winningMap(room));
}

export function setProfile(ws: WebSocket, name?: string, color?: string): Room | string {
  const room = roomFor(ws);
  const player = playerFor(ws);
  if (!room || !player) {
    return 'You are not in a lobby';
  }
  if (room.phase !== 'lobby') {
    return 'Cannot change that after the match has started';
  }
  if (typeof name === 'string') {
    const cleaned = name.replace(/\s+/g, ' ').trim().slice(0, 18);
    player.name = cleaned || 'Player';
  }
  if (typeof color === 'string' && color.length > 0) {
    const hex = normalizeBallColor(color);
    if (!hex) {
      return 'Pick a valid ball colour';
    }
    for (const other of room.players.values()) {
      if (other.id !== player.id && other.color.toLowerCase() === hex.toLowerCase()) {
        return 'That colour is already taken';
      }
    }
    player.color = hex;
  }
  return room;
}

export function setGameMode(ws: WebSocket, mode: string): Room | string {
  const room = roomFor(ws);
  const player = playerFor(ws);
  if (!room || !player) {
    return 'You are not in a lobby';
  }
  if (player.id !== room.hostId) {
    return 'Only the host can change the mode';
  }
  if (room.phase !== 'lobby') {
    return 'Cannot change mode after the match has started';
  }
  room.gameMode = normalizeGameMode(mode);
  return room;
}

export function holeEndPayload(room: Room): {
  t: 'hole_end';
  holeIndex: number;
  lastHole: boolean;
  endsAt: number;
  results: Array<{
    playerId: string;
    name: string;
    color: string;
    strokes: number;
    total: number;
    time: number;
    totalTime: number;
    holed: boolean;
  }>;
} {
  return {
    t: 'hole_end',
    holeIndex: room.roundIndex,
    lastHole: room.roundIndex + 1 >= room.rounds,
    endsAt: Date.now() + HOLE_SUMMARY_MS,
    results: [...room.players.values()].map((p) => ({
      playerId: p.id,
      name: p.name,
      color: p.color,
      strokes: p.strokes,
      total: p.totalStrokes,
      time: p.holeTime,
      totalTime: p.totalTime,
      holed: p.holed,
    })),
  };
}

export function matchPlacings(room: Room): Array<{
  playerId: string;
  name: string;
  color: string;
  total: number;
  time: number;
  place: number;
}> {
  const ffa = room.gameMode === 'free_for_all';
  const ranked = [...room.players.values()].sort((a, b) => compareMatchScore(a, b, ffa));
  const placings: Array<{
    playerId: string;
    name: string;
    color: string;
    total: number;
    time: number;
    place: number;
  }> = [];
  let place = 1;
  ranked.forEach((p, i) => {
    const prev = i > 0 ? ranked[i - 1] : undefined;
    if (prev && !sameMatchPlace(prev, p, ffa)) {
      place = i + 1;
    }
    placings.push({
      playerId: p.id,
      name: p.name,
      color: p.color,
      total: p.totalStrokes,
      time: p.totalTime,
      place,
    });
  });
  return placings;
}

function compareMatchScore(a: Player, b: Player, ffa: boolean): number {
  if (ffa) {
    if (a.totalTime !== b.totalTime) {
      return a.totalTime - b.totalTime;
    }
    if (a.totalStrokes !== b.totalStrokes) {
      return a.totalStrokes - b.totalStrokes;
    }
  } else if (a.totalStrokes !== b.totalStrokes) {
    return a.totalStrokes - b.totalStrokes;
  } else if (a.totalTime !== b.totalTime) {
    return a.totalTime - b.totalTime;
  }
  return a.name.localeCompare(b.name);
}

function sameMatchPlace(a: Player, b: Player, _ffa: boolean): boolean {
  return a.totalStrokes === b.totalStrokes && a.totalTime === b.totalTime;
}

export function markHoled(ws: WebSocket): { room: Room; result: 'player' | 'summary' } | string {
  const room = roomFor(ws);
  const player = playerFor(ws);
  if (!room || !player) {
    return 'You are not in a lobby';
  }
  if (room.phase !== 'playing') {
    return 'That game is not in play';
  }
  player.holed = true;
  player.ball.atRest = true;
  if (player.holeTime <= 0) {
    player.holeTime = Math.max(0, (Date.now() - (room.holeStartedAt || Date.now())) / 1000);
  }
  const finished = tryFinishHole(room);
  return { room, result: finished ?? 'player' };
}

export function tryFinishHole(room: Room): 'summary' | null {
  if (room.phase !== 'playing' || room.summaryPending) {
    return null;
  }
  for (const p of room.players.values()) {
    if (!p.holed) {
      return null;
    }
  }
  for (const p of room.players.values()) {
    p.totalStrokes += p.strokes;
    p.totalTime += p.holeTime;
  }
  room.summaryPending = true;
  room.summaryPhase = 'hole';
  return 'summary';
}

export function continueAfterHole(room: Room): 'vote' | 'over' {
  clearHoleAdvance(room.code);
  room.summaryPending = false;
  room.summaryPhase = '';
  room.roundIndex += 1;
  if (room.roundIndex >= room.rounds) {
    room.phase = 'lobby';
    room.mapId = '';
    return 'over';
  }
  startVote(room);
  return 'vote';
}

export type SummaryAdvance = 'standings' | 'vote' | 'over';

export function advanceSummary(room: Room): { room: Room; result: SummaryAdvance; endsAt?: number } {
  if (room.summaryPhase !== 'standings') {
    room.summaryPhase = 'standings';
    return { room, result: 'standings', endsAt: Date.now() + HOLE_SUMMARY_MS };
  }
  return { room, result: continueAfterHole(room) };
}

export function skipHoleSummary(ws: WebSocket): { room: Room; result: SummaryAdvance; endsAt?: number } | string {
  const room = roomFor(ws);
  const player = playerFor(ws);
  if (!room || !player) {
    return 'You are not in a lobby';
  }
  if (player.id !== room.hostId) {
    return 'Only the host can skip';
  }
  if (!room.summaryPending) {
    return 'Results are not up';
  }
  return advanceSummary(room);
}

export function scheduleHoleAdvance(
  room: Room,
  onDone: (live: Room, result: SummaryAdvance, endsAt?: number) => void
): void {
  clearHoleAdvance(room.code);
  holeAdvanceTimers.set(
    room.code,
    setTimeout(() => {
      holeAdvanceTimers.delete(room.code);
      const live = rooms.get(room.code);
      if (!live || !live.summaryPending) {
        return;
      }
      const next = advanceSummary(live);
      if (next.result === 'standings') {
        scheduleHoleAdvance(live, onDone);
      }
      onDone(live, next.result, next.endsAt);
    }, HOLE_SUMMARY_MS)
  );
}

export function chatFrom(
  ws: WebSocket,
  raw: string
): { room: Room; payload: Record<string, unknown> } | string {
  const room = roomFor(ws);
  const player = playerFor(ws);
  if (!room || !player) {
    return 'You are not in a lobby';
  }
  const text = raw.replace(/\s+/g, ' ').trim().slice(0, 120);
  if (!text) {
    return 'Type a message first';
  }
  return {
    room,
    payload: {
      t: 'chat',
      kind: 'say',
      playerId: player.id,
      name: player.name,
      color: player.color,
      text,
    },
  };
}

export function holeNotice(player: Player): Record<string, unknown> {
  const strokes = player.strokes;
  return {
    t: 'chat',
    kind: 'system',
    playerId: player.id,
    name: player.name,
    text: `${player.name} in · ${strokes}`,
  };
}

export function departureNotice(ws: WebSocket): { room: Room; payload: Record<string, unknown> } | undefined {
  const room = roomFor(ws);
  const player = playerFor(ws);
  if (!room || !player || room.phase !== 'playing') {
    return undefined;
  }
  return {
    room,
    payload: {
      t: 'chat',
      kind: 'system',
      playerId: player.id,
      name: player.name,
      text: `${player.name} left`,
    },
  };
}

export function voteState(room: Room): {
  t: 'vote_state';
  deadline: number;
  votes: Record<string, string>;
  counts: Record<string, number>;
} {
  const votes: Record<string, string> = {};
  const counts: Record<string, number> = {};
  for (const id of MAP_IDS) {
    counts[id] = 0;
  }
  for (const [playerId, mapId] of room.votes) {
    votes[playerId] = mapId;
    counts[mapId] = (counts[mapId] ?? 0) + 1;
  }
  return { t: 'vote_state', deadline: room.voteDeadline, votes, counts };
}

function commitMatch(room: Room, mapId: string): Room {
  clearVoteTimer(room.code);
  room.mapId = mapId;
  room.phase = 'playing';
  room.summaryPending = false;
  room.summaryPhase = '';
  room.votes.clear();
  room.voteDeadline = 0;
  room.takenPickups.clear();
  room.holeStartedAt = Date.now();
  for (const p of room.players.values()) {
    p.strokes = 0;
    p.holeTime = 0;
    p.holed = false;
    p.ball = emptyBall(p.id);
  }
  return room;
}

function startVote(room: Room): void {
  room.phase = 'selecting';
  room.votes.clear();
  room.voteDeadline = Date.now() + VOTE_MS;
  clearVoteTimer(room.code);
  voteTimers.set(
    room.code,
    setTimeout(() => {
      const live = rooms.get(room.code);
      if (!live || live.phase !== 'selecting') {
        return;
      }
      commitMatch(live, winningMap(live));
      onVoteEnded?.(live);
    }, VOTE_MS)
  );
}

function newestPlayer(room: Room): Player | undefined {
  let newest: Player | undefined;
  for (const p of room.players.values()) {
    if (!newest || p.joinedAt > newest.joinedAt) {
      newest = p;
    }
  }
  return newest;
}

function normalizeBallColor(value: string): string | null {
  const raw = value.trim().toUpperCase();
  const hex = raw.startsWith('#') ? raw : `#${raw}`;
  const match = COLORS.find((c) => c.toUpperCase() === hex);
  return match ?? null;
}

function normalizeGameMode(value: string): GameMode {
  return value === 'free_for_all' ? 'free_for_all' : 'turn_by_turn';
}

function clearHoleAdvance(code: string): void {
  const timer = holeAdvanceTimers.get(code);
  if (timer) {
    clearTimeout(timer);
  }
  holeAdvanceTimers.delete(code);
}

function clampRounds(value: number): number {
  if (!Number.isFinite(value)) {
    return 1;
  }
  return Math.min(9, Math.max(1, Math.floor(value)));
}

function winningMap(room: Room): string {
  const counts = new Map<string, number>();
  for (const id of MAP_IDS) {
    counts.set(id, 0);
  }
  for (const mapId of room.votes.values()) {
    counts.set(mapId, (counts.get(mapId) ?? 0) + 1);
  }
  let bestN = -1;
  const tied: string[] = [];
  for (const id of MAP_IDS) {
    const n = counts.get(id) ?? 0;
    if (n > bestN) {
      bestN = n;
      tied.length = 0;
      tied.push(id);
    } else if (n === bestN) {
      tied.push(id);
    }
  }
  const hostVote = room.votes.get(room.hostId);
  if (hostVote && tied.includes(hostVote)) {
    return hostVote;
  }
  return tied[0] ?? MAP_IDS[0] ?? 'rainbow_stairs';
}

function normalizeMapId(mapId: string): string {
  return (MAP_IDS as readonly string[]).includes(mapId) ? mapId : 'rainbow_stairs';
}

function clearVoteTimer(code: string): void {
  const timer = voteTimers.get(code);
  if (timer) {
    clearTimeout(timer);
  }
  voteTimers.delete(code);
}

export function claimPickup(ws: WebSocket, pickupId: string, kind: string): string | undefined {
  const room = roomFor(ws);
  const from = playerFor(ws);
  if (!room || !from || room.phase !== 'playing') {
    return 'Not in a match';
  }
  if (kind !== 'shield' && kind !== 'shrink') {
    return 'Unknown power-up';
  }
  if (!/^[a-z0-9_]{3,32}$/.test(pickupId)) {
    return 'Bad pickup';
  }
  const readyAt = room.takenPickups.get(pickupId) ?? 0;
  if (Date.now() < readyAt) {
    return 'Already taken';
  }
  room.takenPickups.set(pickupId, Date.now() + 18_000);
  broadcast(room, { t: 'pickup_taken', pickupId, playerId: from.id, kind });
  return undefined;
}

export function usePower(ws: WebSocket, kind: string): string | undefined {
  const room = roomFor(ws);
  const from = playerFor(ws);
  if (!room || !from || room.phase !== 'playing') {
    return 'Not in a match';
  }
  if (kind !== 'shield' && kind !== 'shrink') {
    return 'Unknown power-up';
  }
  broadcast(room, { t: 'power_use', playerId: from.id, kind }, ws);
  return undefined;
}

export function snapshot(room: Room): { t: 'snapshot'; balls: BallSnap[] } {
  return { t: 'snapshot', balls: Array.from(room.players.values()).map((p) => p.ball) };
}

export function forwardBump(
  ws: WebSocket,
  targetId: string,
  vx: number,
  vy: number,
  vz: number
): string | undefined {
  const room = roomFor(ws);
  const from = playerFor(ws);
  if (!room || !from || room.phase !== 'playing') {
    return 'Not in a match';
  }
  if (targetId === from.id) {
    return 'Cannot bump yourself';
  }
  let target: Player | undefined;
  for (const p of room.players.values()) {
    if (p.id === targetId) {
      target = p;
      break;
    }
  }
  if (!target) {
    return 'Player not found';
  }
  const cap = 28;
  send(target.ws, {
    t: 'bump',
    fromId: from.id,
    vx: clamp(vx, -cap, cap),
    vy: clamp(vy, -cap, cap),
    vz: clamp(vz, -cap, cap),
  });
  return undefined;
}

function clamp(value: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, value));
}

function emptyBall(id: string): BallSnap {
  return { id, x: 0, y: 0.5, z: 0, vx: 0, vy: 0, vz: 0, atRest: true };
}

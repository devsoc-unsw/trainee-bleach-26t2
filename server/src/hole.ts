import { GameState, Player, Room, Vec3 } from './interface.js';
import { COURSE, getHole } from './course.js';
import { broadcast } from './rooms.js';

const COUNTDOWN_MS = 3 * 1000;

interface HoleEndResult {
  playerId: string;
  strokes: number;
  relToPar: number;
}

export function startCountdown(room: Room, holeIndex: number) {
  room.state = GameState.COUNTDOWN;

  setTimeout(() => {
    if (room.currentHoleIndex !== holeIndex) return;
    const hole = getHole(holeIndex);
    if (!hole) return;

    room.state = GameState.HOLE_ACTIVE;
    broadcast(room, {
      t: 'hole_start',
      holeIndex: holeIndex,
      par: hole.par,
      timerMs: 0, // still unimplemented
      spawn: hole.spawn,
    });
  }, COUNTDOWN_MS);
}


export function distance(a: Vec3, b: Vec3): number {
  const dx = a[0] - b[0], dy = a[1] - b[1], dz = a[2] - b[2];
  return Math.sqrt(dx * dx + dy * dy + dz * dz);
}

function finaliseHole(room: Room, holeIndex: number): HoleEndResult[] | null {
  const hole = getHole(holeIndex);
  if (!hole) return null;

  const results: HoleEndResult[] = [];
  for (const p of room.players.values()) {
    p.holeResults.push({ holeIndex, strokes: p.strokes, par: hole.par, completed: true });
    results.push({ playerId: p.id, strokes: p.strokes, relToPar: p.strokes - hole.par });
    p.strokes = 0;
    p.holedThisHole = false;
  }
  return results;
}

function computePlacings(room: Room): { playerId: string; total: number; place: number }[] {
  const totals = [...room.players.values()].map((p) => {
    const playerTotal = p.holeResults.reduce((sum, r) => sum + r.strokes, 0);
    return { playerId: p.id, total: playerTotal };
  });

  totals.sort((a, b) => a.total - b.total);

  const placings: { playerId: string; total: number; place: number }[] = [];
  let place = 1;
  let prevTotal: number | null = null;

  totals.forEach((entry, i) => {
    if (prevTotal !== null && entry.total !== prevTotal) {
      place = i + 1;
    }
    placings.push({ ...entry, place });
    prevTotal = entry.total;
  });
  return placings;
}

export function handleHoledBallAftermath(room: Room): void {

  const finishedHoleIndex = room.currentHoleIndex;
  const results = finaliseHole(room, finishedHoleIndex);
  if (!results) return;

  broadcast(room, { t: 'hole_end', holeIndex: finishedHoleIndex, results });

  room.currentHoleIndex += 1;

  if (room.currentHoleIndex >= COURSE.length) {
    room.state = GameState.MATCH_END;
    broadcast(room, { t: 'match_end', placings: computePlacings(room) });
  } else {
    startCountdown(room, room.currentHoleIndex);
  }
}
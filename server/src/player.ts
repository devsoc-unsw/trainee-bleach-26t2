import { getHole } from "./course.js";
import { GameState, HoleResult, Player, Room, Vec3 } from "./interface.js";
import { updateRoomLastModified } from "./rooms.js";

const SHOT_RATE_LIMIT_MS = 250;


export function updateBallState(
    player: Player,
    pos: Vec3,
    vel: Vec3,
    atRest: boolean
): void {
  player.pos = pos;
  player.vel = vel;
  player.atRest = atRest;
}


export function canShoot(player: Player, room: Room): { ok: true } | { ok: false; code: string; message: string } {
  if (room.state !== GameState.HOLE_ACTIVE) {
    return { ok: false, code: 'NOT_ACTIVE', message: 'Hole is not active' };
  }
  if (!player.atRest) {
    return { ok: false, code: 'BALL_MOVING', message: 'Ball must be at rest to shoot' };
  }
  if (player.lastShotAt !== 0 && Date.now() - player.lastShotAt < SHOT_RATE_LIMIT_MS) {
    return { ok: false, code: 'RATE_LIMITED', message: 'Shooting too fast' };
  }
  return { ok: true };
}


export function recordStroke(player: Player): number {
  player.strokes += 1;
  player.lastShotAt = Date.now();
  player.atRest = false;
  return player.strokes;
}


export function markHoled(player: Player): void {
  player.holedThisHole = true;
  player.atRest = true;
}
import { GameState, Player, Room, Vec3 } from "./interface.js";
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

export function finaliseHole(): void {

  // for all active players in the room, push their current hole stats, then clear current hole stats for new hole


  // holeIndex should be the room's currentHoleIndex
  // par should be the current hole's HoleConfig

  // if not successful hole:
    // set their result to max(3 + current hole par, strokes)
  // if holedThisHole:
    // push a hole result object
  
  // clear stats
    // involves resetting strokes, holedThisHole, lastShotAt
    // increment room's currentHoleIndex

  // updateRoomLastModified(room)

}

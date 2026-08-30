import { Player, Room, Vec3 } from "./interface.js";
import { updateRoomLastModified } from "./rooms.js";

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

import type { HoleConfig } from './interface.js';

export const COURSE_ID = 'unsw-campus';

export const COURSE: HoleConfig[] = [
  {
    index: 0,
    par: 3,
    spawn: [0, 1, 0],
    cup: [0, 0.1, -63],
    cupTolerance: 0.5,
    name: 'Test Hole',
  },
  {
    index: 0,
    par: 3,
    spawn: [0, 1, 0],
    cup: [0, 0.1, -63],
    cupTolerance: 0.5,
    name: '2nd Test Hole',
  },
];

export function getHole(index: number): HoleConfig | undefined {
  return COURSE[index];
}
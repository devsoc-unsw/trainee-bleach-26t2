import type { HoleConfig } from './interface.js';

export const COURSE_ID = 'unsw-campus';

export const COURSE: HoleConfig[] = [];

export function getHole(index: number): HoleConfig | undefined {
  return COURSE[index];
}
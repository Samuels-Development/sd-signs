import { SIGN_COLOURS } from '@/theme/palette';

/**
 * Mirror of shared/anim.lua. The preview has to agree with the world exactly, so the
 * stepping maths lives in both places rather than the UI approximating it — a preview
 * that drifts from the real effect is worse than no preview.
 */

export type AnimMode = 'off' | 'gradient' | 'cycle' | 'wave' | 'chase' | 'pulse';

export interface AnimModeDef {
  id: AnimMode;
  label: string;
  hint: string;
  dynamic: boolean;
}

export const ANIM_MODES: AnimModeDef[] = [
  { id: 'off', label: 'None', hint: 'Static colour', dynamic: false },
  { id: 'gradient', label: 'Gradient', hint: 'Fixed rainbow', dynamic: false },
  { id: 'cycle', label: 'Cycle', hint: 'All letters shift', dynamic: true },
  { id: 'wave', label: 'Wave', hint: 'Rainbow travels', dynamic: true },
  { id: 'chase', label: 'Chase', hint: 'Runner light', dynamic: true },
  { id: 'pulse', label: 'Pulse', hint: 'Breathes white', dynamic: true },
];

const N = SIGN_COLOURS.length;
const WHITE = 0;

export const isDynamic = (mode: AnimMode): boolean =>
  ANIM_MODES.find((m) => m.id === mode)?.dynamic ?? false;

/** Palette index for one letter at time `t` (seconds). Steps are integral by design. */
export function indexFor(
  mode: AnimMode,
  i: number,
  count: number,
  t: number,
  speed: number,
  base: number,
): number {
  switch (mode) {
    case 'gradient':
      return count <= 1 ? base : Math.floor((i / count) * N) % N;
    case 'cycle':
      return Math.floor(t * speed) % N;
    case 'wave':
      return (Math.floor(t * speed) + i) % N;
    case 'chase':
      return i === Math.floor(t * speed) % Math.max(1, count) ? WHITE : base;
    case 'pulse':
      return Math.floor(t * speed) % 2 === 0 ? base : WHITE;
    default:
      return base;
  }
}

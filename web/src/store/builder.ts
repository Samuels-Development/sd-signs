import { create } from 'zustand';
import type { AnimMode } from '@/lib/anim';
import { SIGN_COLOURS } from '@/theme/palette';

export type SignStyle = 'painted' | 'neon';

export interface Limits {
  maxLength: number;
  minSize: number;
  maxSize: number;
  minThickness: number;
  maxThickness: number;
  minTracking: number;
  maxTracking: number;
  maxPerPlayer: number | null;
  /** Max rows in one sign; maxLength applies PER ROW. */
  maxRows: number;
  /** Upper bound on the per-sign visibility slider, metres. */
  maxRenderDistance: number;
  /** Config.RenderDistance: what a sign with no stored value falls back to. */
  renderDistance: number;
}

export interface Draft {
  text: string;
  /** Base colour, used for any character without an override. */
  colour: string;
  /** "painted" = matte, "neon" = emissive face that glows at night. */
  style: SignStyle;
  /** Colour animation mode. */
  anim: AnimMode;
  /** Animation steps per second. */
  animSpeed: number;
  /** Rotation about the vertical axis, degrees per second. 0 = static. */
  spin: number;
  /**
   * Per-character palette digits, one per character of `text` (spaces included so
   * indices line up). Always the same length as the text, or empty when the whole
   * sign is one colour.
   */
  colours: string;
  size: number;
  thickness: number;
  tracking: number;
  /**
   * How far away this sign stays spawned, metres. null means "use the server default",
   * which is what every sign placed before this slider existed stores.
   */
  renderDistance: number | null;
}

export interface Measurement {
  width: number;
  letters: number;
}

export interface PlacedSign {
  id: number;
  text: string;
  colour: string;
  colours?: string | null;
  style?: SignStyle | null;
  anim?: AnimMode | null;
  animSpeed?: number | null;
  spin?: number | null;
  size: number;
  thickness: number;
  tracking: number;
  renderDistance?: number | null;
  x: number;
  y: number;
  z: number;
  heading: number;
  owner?: string;
  distance: number;
  spawned: boolean;
}

/**
 * Fallbacks only — the real values arrive with the open payload from Config.Limits.
 * They must still mirror configs/config.lua: these bound the sliders for the moment
 * before the payload lands, and they are what the standalone dev build uses.
 */
const DEFAULT_LIMITS: Limits = {
  maxLength: 24,
  minSize: 0.2,
  maxSize: 120.0,
  minThickness: 0.25,
  maxThickness: 8.0,
  minTracking: -0.3,
  maxTracking: 1.5,
  maxPerPlayer: null,
  maxRows: 3,
  maxRenderDistance: 3200.0,
  renderDistance: 120.0,
};

export const colourIndex = (id: string): number => {
  const i = SIGN_COLOURS.findIndex((c) => c.id === id);
  return i < 0 ? 0 : i;
};

export const colourAt = (draft: Draft, index: number): string => {
  const d = draft.colours[index];
  if (!d) return draft.colour;
  return SIGN_COLOURS[Number(d)]?.id ?? draft.colour;
};

/** Grow/shrink the per-character digits to match the text, padding with the base. */
function fitColours(colours: string, text: string, base: string): string {
  if (!colours) return '';
  const pad = String(colourIndex(base));
  if (colours.length >= text.length) return colours.slice(0, text.length);
  return colours + pad.repeat(text.length - colours.length);
}

export type Tab = 'build' | 'placed';

export type PlacementMode = 'raycast' | 'gizmo';

export interface Placement {
  /** How the next placement will be dragged. */
  mode: PlacementMode;
  /** Whether the optional object_gizmo resource is actually running. */
  gizmo: boolean;
  /** Config.Placement.allowSwitch: false hides the control entirely. */
  allowSwitch: boolean;
}

/**
 * Assume no gizmo until the open payload says otherwise. Guessing `true` would offer
 * a mode that cannot run; guessing `false` only means the control flickers on once,
 * on a server that has it.
 */
const DEFAULT_PLACEMENT: Placement = {
  mode: 'raycast',
  gizmo: false,
  allowSwitch: true,
};

interface BuilderState {
  open: boolean;
  tab: Tab;
  draft: Draft;
  limits: Limits;
  placement: Placement;
  measure: Measurement;
  /** Character index being painted, or null for "the whole sign". */
  selected: number | null;
  signs: PlacedSign[];
  /** Sign id being edited, or null when building a new one. */
  editing: number | null;

  openPanel: (p: {
    tab?: Tab; draft?: Partial<Draft>; limits?: Partial<Limits>;
    signs?: PlacedSign[]; editing?: number | null; placement?: Partial<Placement>;
  }) => void;
  setPlacementMode: (mode: PlacementMode) => void;
  setTab: (tab: Tab) => void;
  edit: (sign: PlacedSign) => void;
  cancelEdit: () => void;
  close: () => void;
  patch: (patch: Partial<Draft>) => void;
  setText: (text: string) => void;
  select: (index: number | null) => void;
  paint: (colourId: string) => void;
  setMeasure: (m: Measurement) => void;
  setSigns: (signs: PlacedSign[]) => void;
}

export const useBuilder = create<BuilderState>((set) => ({
  open: false,
  tab: 'build',
  editing: null,
  draft: {
    text: 'LOS SANTOS', colour: 'white', colours: '', style: 'painted',
    anim: 'off', animSpeed: 2, spin: 0,
    size: 1, thickness: 1, tracking: 0.12, renderDistance: null,
  },
  limits: DEFAULT_LIMITS,
  placement: DEFAULT_PLACEMENT,
  measure: { width: 0, letters: 0 },
  selected: null,
  signs: [],

  openPanel: ({ tab, draft, limits, signs, editing, placement }) =>
    set((s) => ({
      open: true,
      tab: tab ?? s.tab,
      selected: null,
      editing: editing ?? null,
      draft: { ...s.draft, colours: '', ...draft },
      limits: { ...s.limits, ...limits },
      placement: { ...s.placement, ...placement },
      signs: signs ?? s.signs,
    })),

  setPlacementMode: (mode) =>
    set((s) => ({ placement: { ...s.placement, mode } })),

  setTab: (tab) => set({ tab, selected: null }),

  /** Load a placed sign into the builder tab for editing. */
  edit: (sign) =>
    set({
      tab: 'build',
      editing: sign.id,
      selected: null,
      draft: {
        text: sign.text,
        colour: sign.colour,
        colours: sign.colours ?? '',
        style: sign.style ?? 'painted',
        anim: sign.anim ?? 'off',
        animSpeed: sign.animSpeed ?? 2,
        spin: sign.spin ?? 0,
        size: sign.size,
        thickness: sign.thickness,
        tracking: sign.tracking,
        renderDistance: sign.renderDistance ?? null,
      },
    }),

  /**
   * Leaving edit mode also returns to the list you came from.
   *
   * Not cosmetic: the live preview floats a copy in front of the camera whenever the
   * Build tab is open with no `editing` id. Clearing `editing` while staying on Build
   * leaves the edited sign's text in the draft, so it floats a clone right next to
   * the original and reads as though cancelling duplicated the sign.
   */
  cancelEdit: () => set({ editing: null, selected: null, tab: 'placed' }),
  close: () => set({ open: false, selected: null, editing: null }),

  patch: (patch) => set((s) => ({ draft: { ...s.draft, ...patch } })),

  setText: (text) =>
    set((s) => {
      // Clamp rows and per-row length HERE rather than on the textarea, so a paste is
      // held to the same limits as typing. Lua re-clamps regardless; this is feedback,
      // not the boundary.
      const clamped = text
        .replace(/\r\n?/g, '\n')
        .split('\n')
        .slice(0, s.limits.maxRows)
        .map((row) => Array.from(row).slice(0, s.limits.maxLength).join(''))
        .join('\n');
      return {
        draft: {
          ...s.draft,
          text: clamped,
          colours: fitColours(s.draft.colours, clamped, s.draft.colour),
        },
        // A selection past the end of the new text would paint nothing.
        selected: s.selected !== null && s.selected >= clamped.length ? null : s.selected,
      };
    }),

  select: (selected) => set({ selected }),

  paint: (colourId) =>
    set((s) => {
      const { draft, selected } = s;
      if (selected === null) {
        // Whole sign: drop the per-character overrides entirely rather than
        // rewriting every digit, so "all one colour" stays represented as empty.
        return { draft: { ...draft, colour: colourId, colours: '' } };
      }
      const base = draft.colours || String(colourIndex(draft.colour)).repeat(draft.text.length);
      const next =
        base.slice(0, selected) + String(colourIndex(colourId)) + base.slice(selected + 1);
      return { draft: { ...draft, colours: next } };
    }),

  setMeasure: (measure) => set({ measure }),
  setSigns: (signs) => set({ signs }),
}));

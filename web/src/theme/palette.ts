/**
 * Sign colours are the exact sRGB values baked into the prop palette texture
 * (verified byte-for-byte against alphabet_palette.png), so what the builder shows
 * is what the letters render as in world. Keep these in step with PALETTE in
 * assets/alphabet3d/build_alphabet3d.py.
 */
export const SIGN_COLOURS = [
  { id: 'white', label: 'White', hex: '#FFFFFF' },
  { id: 'red', label: 'Red', hex: '#FF1A14' },
  { id: 'orange', label: 'Orange', hex: '#FF610D' },
  { id: 'amber', label: 'Amber', hex: '#FFA814' },
  { id: 'yellow', label: 'Yellow', hex: '#FFF026' },
  { id: 'green', label: 'Green', hex: '#29F240' },
  { id: 'cyan', label: 'Cyan', hex: '#1AE6FF' },
  { id: 'blue', label: 'Blue', hex: '#1A59FF' },
  { id: 'purple', label: 'Purple', hex: '#8C33FF' },
  { id: 'pink', label: 'Pink', hex: '#FF26A6' },
] as const;

export type SignColourId = (typeof SIGN_COLOURS)[number]['id'];

export function colourHex(id: string): string {
  return SIGN_COLOURS.find((c) => c.id === id)?.hex ?? '#FFFFFF';
}

/** UI chrome. Deliberately near-neutral so the selected sign colour is the only hue. */
const hex = {
  canvas: '#07080a',
  panel: '#101317',
  raise: '#171b21',
  line: '#252b33',
  text: '#e8ebef',
  muted: '#8b95a1',
  faint: '#5b646e',
  /** The dark metal of the letter returns, reused for the preview's extrusion. */
  returns: '#1d1d21',
  danger: '#f14c4c',
} as const;

export type ChromeKey = keyof typeof hex;
export const chrome: Record<ChromeKey, string> = hex;

function toTriple(value: string): string {
  const n = parseInt(value.slice(1), 16);
  return `${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}`;
}

/** rgba() from any hex, for glows and translucent fills. */
export function alpha(value: string, a: number): string {
  return `rgba(${toTriple(value)}, ${a})`;
}

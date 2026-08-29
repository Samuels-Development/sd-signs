import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { type AnimMode, indexFor, isDynamic } from '@/lib/anim';
import { SIGN_COLOURS, alpha, chrome, colourHex } from '@/theme/palette';

/**
 * Montserrat Bold's cap height as a fraction of its em box (OS/2 sCapHeight 700
 * over unitsPerEm 1000). The props are modelled at cap height = 1.0 and tracking is
 * expressed in those cap-height units, so converting through this constant keeps the
 * preview's letter spacing honest.
 */
const CAP_PER_EM = 0.7;

/**
 * Depth of the preview's faked extrusion, px. Constant on purpose.
 *
 * This used to track the thickness slider, which does not survive contact with the
 * rest of the preview: the extrusion is a stack of flat 2D shadows, but the preview
 * also spins on rotateY, and a flat stack cannot rotate with the glyphs. At the top
 * of the slider it reached ~43 layers and read as a diagonal smear rather than depth.
 *
 * Thickness is shown where it can be shown honestly -- on the live sign in the world.
 * Here it stays a fixed bevel that says "channel letter" without claiming a value.
 */
const EXTRUDE_PX = 3;

/** Horizontal breathing room inside the preview box, px. */
const GUTTER = 28;

/**
 * Vertical breathing room, px. Smaller than the horizontal gutter because the box is
 * much shorter than it is wide, so the same inset would eat most of the height.
 */
const GUTTER_Y = 14;

interface Props {
  text: string;
  /** Colour name per character index. */
  colourOf: (index: number) => string;
  tracking: number;
  /** Emissive finish: brighter halo, matching how the prop reads at night. */
  neon?: boolean;
  anim?: AnimMode;
  animSpeed?: number;
  /** Degrees per second of 3D rotation. */
  spin?: number;
  /** Palette index of the sign base colour, for modes that keep it. */
  baseIndex?: number;
  /** Character index currently being painted, or null for the whole sign. */
  selected?: number | null;
  onSelect?: (index: number | null) => void;
}

export function SignPreview({
  text,
  colourOf,
  tracking,
  neon = false,
  anim = 'off',
  animSpeed = 2,
  spin = 0,
  baseIndex = 0,
  selected = null,
  onSelect,
}: Props) {
  const boxRef = useRef<HTMLDivElement>(null);
  const textRef = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(1);
  const [tick, setTick] = useState(0);

  const empty = text.trim().length === 0;
  const chars = empty ? ['—'] : Array.from(text);

  // Shrink-to-fit on BOTH axes. offsetWidth/offsetHeight are the element's
  // *untransformed* layout size, so they stay stable no matter what scale we have
  // already applied -- measuring scrollWidth instead gives the clamped box width and
  // long text silently overflows.
  //
  // Height matters as much as width now that a sign can have rows: the box is a fixed
  // 158px with overflow hidden, so fitting on width alone lets a three-row sign
  // render at full size and get its top and bottom rows cropped off.
  const fit = useCallback(() => {
    const box = boxRef.current;
    const el = textRef.current;
    if (!box || !el) return;
    const availW = box.clientWidth - GUTTER * 2;
    const availH = box.clientHeight - GUTTER_Y * 2;
    const natW = el.offsetWidth;
    const natH = el.offsetHeight;
    if (availW <= 0 || natW <= 0 || availH <= 0 || natH <= 0) return;
    setScale(Math.min(1, Math.max(0.08, Math.min(availW / natW, availH / natH))));
  }, []);

  useLayoutEffect(fit, [fit, text, tracking]);

  useEffect(() => {
    const box = boxRef.current;
    if (!box) return;
    const ro = new ResizeObserver(fit);
    ro.observe(box);
    const raf = requestAnimationFrame(fit);
    void document.fonts?.ready.then(fit).catch(() => {});
    return () => {
      ro.disconnect();
      cancelAnimationFrame(raf);
    };
  }, [fit]);

  // Repaint while a dynamic mode is selected. Throttled to the same 15 Hz the world
  // runs at, so the preview steps in lockstep with the props rather than looking
  // smoother than the thing it is previewing.
  useEffect(() => {
    if (!isDynamic(anim)) return;
    const id = setInterval(() => setTick((n) => n + 1), 1000 / 15);
    return () => clearInterval(id);
  }, [anim]);

  // Rotation is driven here rather than by a CSS keyframe animation, because it has
  // to be interruptible. A spinning sign is nearly impossible to click a letter on --
  // near 90 degrees a glyph is only a few pixels wide -- so reaching for the preview
  // eases it back to face-on and holds it there. A plain `animation-play-state:
  // paused` would freeze it at whatever angle it happened to be at, which can be the
  // exact edge-on angle you could not click in the first place.
  const [angle, setAngle] = useState(0);
  const angleRef = useRef(0);
  const holdRef = useRef(false);
  const frozen = selected !== null;

  // Driven by setInterval rather than requestAnimationFrame, matching the colour
  // ticker above. Elapsed time is measured from the clock rather than assumed from
  // the interval, so a late or coalesced tick advances the angle by the right amount
  // instead of the rotation quietly running slow.
  useEffect(() => {
    if (spin <= 0 && angleRef.current === 0) return;
    let last = performance.now();
    const id = setInterval(() => {
      const now = performance.now();
      const dt = Math.min(0.25, (now - last) / 1000);
      last = now;

      if (holdRef.current || frozen || spin <= 0) {
        // Ease to the nearest face-on angle by the shortest path, so the letters end
        // up at full width and clickable rather than frozen edge-on.
        const target = Math.round(angleRef.current / 360) * 360;
        const next = angleRef.current + (target - angleRef.current) * Math.min(1, dt * 7);
        angleRef.current = Math.abs(target - next) < 0.05 ? target : next;
      } else {
        angleRef.current = (angleRef.current + spin * dt) % 360;
      }
      setAngle(angleRef.current);
    }, 1000 / 60);
    return () => clearInterval(id);
  }, [spin, frozen]);

  // Fake a shallow extrusion with stacked shadows, at a fixed depth -- see EXTRUDE_PX.
  const extrude = Array.from(
    { length: EXTRUDE_PX },
    (_, i) => `${i + 1}px ${i + 1}px 0 ${chrome.returns}`,
  ).join(', ');

  // Same maths as shared/anim.lua, so the preview cannot drift from the world.
  const t = tick / 15;
  const effectiveColour = (i: number): string => {
    if (anim === 'off') return colourOf(i);
    const idx = indexFor(anim, i, chars.length, t, animSpeed, baseIndex);
    return SIGN_COLOURS[idx]?.id ?? colourOf(i);
  };

  const first = colourHex(effectiveColour(0));

  return (
    <div
      ref={boxRef}
      className="sa-preview"
      style={{
        background: `radial-gradient(120% 140% at 50% 0%, ${alpha(first, neon ? 0.2 : 0.09)} 0%, ${chrome.canvas} 62%)`,
      }}
      onClick={() => onSelect?.(null)}
      onPointerEnter={() => { holdRef.current = true; }}
      onPointerLeave={() => { holdRef.current = false; }}
    >
      <div ref={textRef} className="sa-preview__text" style={{ transform: `translate(-50%, -50%) scale(${scale})` }}>
        {/* Separate element: the outer one owns translate+scale from JS, so a CSS
            transform animation here would overwrite it rather than compose. */}
        <div
          className="sa-preview__spin"
          style={{ transform: `rotateY(${angle}deg)` }}
        >
        {chars.map((ch, i) => {
          // Newlines are real characters in `text` and carry their own slot in the
          // per-character colour string, so they are rendered as a break and NOT
          // skipped -- dropping them here would shift every later index by one and
          // paint the wrong letters.
          if (ch === '\n') return <div key={i} className="sa-preview__break" />;
          const hex = colourHex(effectiveColour(i));
          const isSel = selected === i;
          return (
            <span
              key={i}
              className={`sa-glyph ${isSel ? 'is-selected' : ''} ${onSelect ? 'is-clickable' : ''}`}
              style={{
                color: hex,
                marginRight: `${tracking * CAP_PER_EM}em`,
                textShadow: neon
                  ? `${extrude}, 0 0 10px ${alpha(hex, 0.95)}, 0 0 30px ${alpha(hex, 0.75)}, 0 0 72px ${alpha(hex, 0.5)}`
                  : `${extrude}, 0 0 22px ${alpha(hex, 0.5)}, 0 0 60px ${alpha(hex, 0.25)}`,
                // Undo the shrink so the marker is the same thickness at any scale.
                ...(isSel ? { boxShadow: `inset 0 -${Math.max(2, 4 / scale)}px 0 0 ${hex}` } : {}),
              }}
              onClick={(e) => {
                if (!onSelect || empty || ch === ' ') return;
                e.stopPropagation();
                onSelect(isSel ? null : i);
              }}
            >
              {ch === ' ' ? ' ' : ch}
            </span>
          );
        })}
        </div>
      </div>
      <div className="sa-preview__baseline" style={{ background: alpha(first, 0.28) }} />
    </div>
  );
}

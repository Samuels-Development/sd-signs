import type { ReactNode } from 'react';

interface Props {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  /** Rendered next to the label, e.g. "1.40 m". */
  format: (v: number) => string;
  onChange: (v: number) => void;
  /** Optional control in the head, beside the readout — e.g. a range toggle. */
  action?: ReactNode;
}

/**
 * Deliberately colour-agnostic. The sliders used to be tinted with the selected sign
 * colour, which made a property of the letters look like a theme for the whole panel.
 */
export function Slider({ label, value, min, max, step, format, onChange, action }: Props) {
  // Clamped so a value above the current maximum cannot paint the fill past the end of
  // the track: the size slider's ceiling moves, and a sign built beyond it stays at its
  // real value until the wider range is turned back on.
  const pct = max === min ? 0 : Math.min(100, Math.max(0, ((value - min) / (max - min)) * 100));
  return (
    <label className="sa-slider">
      <span className="sa-slider__head">
        <span className="sa-slider__label">{label}</span>
        <span className="sa-slider__aside">
          {action}
          <span className="sa-slider__value">{format(value)}</span>
        </span>
      </span>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(parseFloat(e.target.value))}
        style={{
          background: `linear-gradient(to right, #7d8895 0%, #7d8895 ${pct}%, #252b33 ${pct}%, #252b33 100%)`,
        }}
      />
    </label>
  );
}

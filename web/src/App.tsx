import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { Check, LayoutGrid, MapPin, Move, Palette, Sparkles, Type, X } from 'lucide-react';
import { PlacedList } from '@/components/PlacedList';
import { SignPreview } from '@/components/SignPreview';
import { Slider } from '@/components/Slider';
import { useNuiEvent } from '@/hooks/useNuiEvent';
import { fetchNui, isEnvBrowser } from '@/nui/bridge';
import {
  colourAt, useBuilder,
  type Draft, type Limits, type PlacedSign, type Tab, type Placement, type PlacementMode,
} from '@/store/builder';
import { ANIM_MODES, isDynamic } from '@/lib/anim';
import { SIGN_COLOURS, alpha, chrome, colourHex } from '@/theme/palette';

interface OpenPayload {
  tab?: Tab;
  draft?: Partial<Draft>;
  limits?: Partial<Limits>;
  signs?: PlacedSign[];
  editing?: number | null;
  placement?: Partial<Placement>;
}

export default function App() {
  const {
    open, tab, draft, limits, measure, selected, signs, editing,
    openPanel, setTab, close, patch, setText, select, paint, setMeasure, cancelEdit,
    placement, setPlacementMode,
  } = useBuilder();
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const morphRef = useRef<HTMLDivElement>(null);
  const [bodyHeight, setBodyHeight] = useState<number | undefined>(undefined);
  // The Build tab is the taller, more variable pane, so it sets the panel height and
  // the Placed tab matches it -- the panel then stops resizing as you switch tabs.
  const [buildHeight, setBuildHeight] = useState<number | undefined>(undefined);
  const tabRef = useRef(tab);
  tabRef.current = tab;

  // Animate the panel's height as well as its width, otherwise switching tabs snaps
  // the box to a new height mid-slide and the whole transition reads as broken.
  // A ResizeObserver on the INNER content drives the OUTER wrapper's height --
  // observing the element whose height you are setting would feed back on itself.
  // It also fires continuously while the width eases, so the height tracks the
  // reflow instead of being measured once at the wrong width.
  useLayoutEffect(() => {
    const inner = morphRef.current;
    if (!inner) return;
    const measure = () => {
      const h = inner.offsetHeight;
      setBodyHeight(h);
      // Remember the Build tab's height so the Placed tab can match it. Only sampled
      // on Build, because on Placed the inner element is stretched to whatever height
      // we already imposed -- reading it back there would just echo our own value.
      if (tabRef.current === 'build') setBuildHeight(h);
    };
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(inner);
    return () => ro.disconnect();
  }, []);

  useNuiEvent<OpenPayload>('signs:open', (d) => openPanel(d ?? {}));
  useNuiEvent('signs:close', () => close());

  const dismiss = useCallback(() => {
    close();
    void fetchNui('signs:close');
  }, [close]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      // Esc peels back one layer at a time: letter selection, then edit mode, then
      // the panel. Losing a filled-in form to a stray Esc is infuriating.
      if (tab === 'build' && selected !== null) select(null);
      else if (tab === 'build' && editing !== null) cancelEdit();
      else dismiss();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, tab, selected, editing, select, cancelEdit, dismiss]);

  useEffect(() => {
    if (open && tab === 'build') inputRef.current?.focus();
  }, [open, tab]);

  // Ask Lua for the real width, debounced: it fires on every keystroke and slider tick.
  useEffect(() => {
    if (!open || tab !== 'build') return;
    const t = setTimeout(async () => {
      const res = await fetchNui<{ width: number; letters: number }>('signs:builder:measure', {
        text: draft.text, size: draft.size, tracking: draft.tracking,
      });
      if (res) setMeasure({ width: res.width, letters: res.letters });
    }, 120);
    return () => clearTimeout(t);
  }, [open, tab, draft.text, draft.size, draft.tracking, setMeasure]);

  // Push the form into the world so a real sign floats in front of the camera while
  // you edit. Debounced, and only while the Build tab is up -- the Placed tab and a
  // closed panel both tear it down so nothing is left hanging in the air.
  useEffect(() => {
    if (!open || tab !== 'build') {
      void fetchNui('signs:builder:preview', { visible: false });
      return;
    }
    const t = setTimeout(() => {
      // `editing` routes this to the real sign instead of a floating copy.
      void fetchNui('signs:builder:preview', { ...draft, editing, visible: true });
    }, 90);
    return () => clearTimeout(t);
  }, [open, tab, draft, editing]);

  const place = useCallback(() => {
    if (!draft.text.trim()) return;
    close();
    void fetchNui('signs:builder:place', draft);
  }, [draft, close]);

  const save = useCallback(async () => {
    if (editing === null) return;
    const id = editing;
    // Leave edit mode BEFORE awaiting anything. Doing it after the round trip leaves
    // a window where the Build tab is open with no editing id, which makes the live
    // preview float a copy of the sign being saved.
    cancelEdit();
    await fetchNui('signs:builder:save', { ...draft, id });
    const res = await fetchNui<{ signs: PlacedSign[] }>('signs:overview:refresh');
    if (res?.signs) useBuilder.getState().setSigns(res.signs);
  }, [draft, editing, cancelEdit]);

  // Mode is a client-side tool preference, so Lua is told directly rather than it
  // riding along in the draft -- it must never end up saved on a sign record.
  const setPlacement = useCallback((mode: PlacementMode) => {
    setPlacementMode(mode);
    void fetchNui('signs:builder:mode', { mode });
  }, [setPlacementMode]);

  const move = useCallback(() => {
    if (editing === null) return;
    close();
    void fetchNui('signs:builder:move', { ...draft, id: editing });
  }, [draft, editing, close]);

  if (!open && !isEnvBrowser()) return null;

  const rows = draft.text.split(String.fromCharCode(10));
  const longest = Math.max(...rows.map((r) => Array.from(r).length));
  const overLength = longest > limits.maxLength || rows.length > limits.maxRows;
  // Deliberately NOT gated on `measure`: that arrives from an async Lua round trip,
  // so gating on it leaves the primary button dead for the first ~120 ms and forever
  // if the callback ever fails. The server re-validates and rejects empty signs.
  const canPlace = draft.text.trim().length > 0;
  const selectedChar = selected !== null ? Array.from(draft.text)[selected] : null;
  // Chrome stays deliberately neutral. The sign colour belongs to the sign, not to
  // the furniture around it.
  const paintingHex = colourHex(selected !== null ? colourAt(draft, selected) : draft.colour);

  return (
    <div className="sa-root">
      {/* One panel that widens on the Placed tab rather than two separate menus. */}
      <div className={`sa-panel ${tab === 'placed' ? 'is-wide' : ''}`}>
        <header className="sa-header">
          <nav className="sa-tabs">
            <button
              className={`sa-tab ${tab === 'build' ? 'is-active' : ''}`}
              onClick={() => setTab('build')}
            >
              <Type size={14} strokeWidth={2.5} />
              {editing !== null ? `Editing #${editing}` : 'Build'}
            </button>
            <button
              className={`sa-tab ${tab === 'placed' ? 'is-active' : ''}`}
              onClick={() => setTab('placed')}
            >
              <LayoutGrid size={14} strokeWidth={2.5} />
              Placed
              <span className="sa-badge">{signs.length}</span>
            </button>
          </nav>
          <button className="sa-iconbtn" onClick={dismiss} title="Close (Esc)">
            <X size={16} />
          </button>
        </header>

        <div
          className="sa-morph"
          style={{ height: tab === 'placed' ? (buildHeight ?? bodyHeight) : bodyHeight }}
        >
          <div ref={morphRef} className={tab === 'placed' ? 'sa-morph__inner is-placed' : 'sa-morph__inner'}>
            {/* Keyed so React remounts it on a tab change and the entry animation
                replays. The key lives HERE and not on the measured element above:
                remounting that one would leave the ResizeObserver watching a detached
                node, and the panel would stop tracking its own height.

                Direction follows the tab order -- Placed sits right of Build, so
                moving right brings content in from the right. It shares the panel's
                easing and duration, so the box resizing and the content arriving read
                as one movement rather than three effects that happen to overlap. */}
            <div
              key={tab}
              className="sa-swap"
              style={{ ['--sa-swap-from' as string]: tab === 'placed' ? '18px' : '-18px' }}
            >
            {tab === 'placed' ? (
              <PlacedList />
            ) : (
              <>
            <SignPreview
              text={draft.text}
              colourOf={(i) => colourAt(draft, i)}
              tracking={draft.tracking}
              neon={draft.style === 'neon'}
              anim={draft.anim}
              animSpeed={draft.animSpeed}
              spin={draft.spin}
              baseIndex={SIGN_COLOURS.findIndex((c) => c.id === draft.colour)}
              selected={selected}
              onSelect={select}
            />

            <div className="sa-body">
              <label className="sa-field">
                <span className="sa-field__label">
                  Text
                  <span className={`sa-count ${overLength ? 'is-over' : ''}`}>
                    {rows.length}/{limits.maxRows} rows &middot; {longest}/{limits.maxLength}
                  </span>
                </span>
                <textarea
                  ref={inputRef}
                  className="sa-input sa-input--rows"
                  value={draft.text}
                  rows={limits.maxRows}
                  placeholder="LOS SANTOS"
                  onChange={(e) => setText(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key !== 'Enter') return;
                    // Enter now inserts a row, so the commit shortcut moves to
                    // Ctrl/Cmd+Enter -- a textarea has no other way to submit.
                    if (e.ctrlKey || e.metaKey) {
                      e.preventDefault();
                      if (editing !== null) void save();
                      else if (canPlace) place();
                      return;
                    }
                    // Swallow the newline once the row limit is reached, rather than
                    // letting the store silently discard it after the fact.
                    if (rows.length >= limits.maxRows) e.preventDefault();
                  }}
                />
                <span className="sa-hint">
                  A–Z, a–z, 0–9, spaces and {'! ? & @ # $ % + - = / < > ( ) . , : \' " ° € £ → ½ …'}
                </span>
              </label>

              <div className="sa-field">
                <span className="sa-field__label">
                  Colour
                  <span className="sa-target" style={{ color: paintingHex }}>
                    <Palette size={11} strokeWidth={2.5} />
                    {selectedChar !== null ? `letter ${selected! + 1} “${selectedChar}”` : 'whole sign'}
                  </span>
                </span>
                <div className="sa-swatches">
                  {SIGN_COLOURS.map((c) => {
                    const isCurrent = paintingHex === c.hex;
                    return (
                      <button
                        key={c.id}
                        title={c.label}
                        onClick={() => paint(c.id)}
                        className={`sa-swatch ${isCurrent ? 'is-active' : ''}`}
                        style={{
                          background: c.hex,
                          boxShadow: isCurrent
                            ? `0 0 0 2px ${chrome.panel}, 0 0 0 3.5px ${c.hex}, 0 0 16px ${alpha(c.hex, 0.55)}`
                            : `0 0 10px ${alpha(c.hex, 0.22)}`,
                        }}
                      />
                    );
                  })}
                </div>
                <span className="sa-hint">
                  {selected !== null ? (
                    <>
                      Painting one letter.{' '}
                      <button className="sa-link" onClick={() => select(null)}>
                        Back to whole sign
                      </button>
                    </>
                  ) : (
                    'Click a letter in the preview above to colour it on its own.'
                  )}
                </span>
              </div>

              <div className="sa-field">
                <span className="sa-field__label">Finish</span>
                <div className="sa-seg">
                  {([
                    { id: 'painted', label: 'Painted', hint: 'Matte face' },
                    { id: 'neon', label: 'Neon', hint: 'Glows at night' },
                  ] as const).map((opt) => (
                    <button
                      key={opt.id}
                      className={`sa-seg__btn ${draft.style === opt.id ? 'is-active' : ''}`}
                      onClick={() => patch({ style: opt.id })}
                    >
                      <b>{opt.label}</b>
                      <span>{opt.hint}</span>
                    </button>
                  ))}
                </div>
              </div>

              <div className="sa-field">
                <span className="sa-field__label">
                  Effect
                  {isDynamic(draft.anim) && (
                    <span className="sa-target sa-target--dim">
                      <Sparkles size={11} strokeWidth={2.5} />
                      costs extra entities
                    </span>
                  )}
                </span>
                <div className="sa-chips">
                  {ANIM_MODES.map((m) => (
                    <button
                      key={m.id}
                      title={m.hint}
                      className={`sa-chip ${draft.anim === m.id ? 'is-active' : ''}`}
                      onClick={() => patch({ anim: m.id })}
                    >
                      {m.label}
                    </button>
                  ))}
                </div>
                <span className="sa-hint">
                  {ANIM_MODES.find((m) => m.id === draft.anim)?.hint}
                  {draft.anim === 'chase' || draft.anim === 'pulse'
                    ? ' — uses your colour plus white.'
                    : draft.anim === 'cycle' || draft.anim === 'wave'
                      ? ' — runs the full palette.'
                      : ''}
                </span>
              </div>

              {isDynamic(draft.anim) && (
                <Slider
                  label="Speed" value={draft.animSpeed} min={0.25} max={10} step={0.25}
                  format={(v) => `${v.toFixed(2)} steps/s`}
                  onChange={(animSpeed) => patch({ animSpeed })}
                />
              )}

              {/* Sliders pair up two to a row. The panel is tall enough that the last
                  controls sat below the fold otherwise, and a slider needs width for
                  its track, not height. */}
              <div className="sa-pair">
              <Slider
                label="Spin" value={draft.spin} min={0} max={120} step={5}
                format={(v) => (v === 0 ? 'off' : `${v.toFixed(0)}°/s`)}
                onChange={(spin) => patch({ spin })}
              />

              <Slider
                label="Size" value={draft.size} min={limits.minSize} max={limits.maxSize} step={0.05}
                format={(v) => `${v.toFixed(2)} m caps`} onChange={(size) => patch({ size })}
              />
              <Slider
                label="Thickness" value={draft.thickness} min={limits.minThickness}
                max={limits.maxThickness} step={0.05}
                format={(v) => `${(v * 0.12).toFixed(3)} m deep`}
                onChange={(thickness) => patch({ thickness })}
              />
              {/* "Tracking" is the typographic term, but the readout is in metres:
                  the stored value is in cap-height units so it scales with the sign,
                  which makes the raw number hard to picture. Range comes from
                  Config.Limits, so widening it there widens this. */}
              <Slider
                label="Letter spacing" value={draft.tracking} min={limits.minTracking}
                max={limits.maxTracking} step={0.01}
                format={(v) => {
                  const m = v * draft.size;
                  if (v < 0) return `${m.toFixed(2)} m — tightened`;
                  return `${m.toFixed(2)} m gap`;
                }}
                onChange={(tracking) => patch({ tracking })}
              />
              </div>

              <div className="sa-readout">
                <span><b>{measure.letters}</b> letters</span>
                <span className="sa-readout__sep" />
                <span><b>{measure.width.toFixed(2)} m</b> wide</span>
              </div>

              {/* Collapses to one column when Config.Placement.allowSwitch is off, so
                  the range slider does not sit at half width beside an empty cell. */}
              <div className={`sa-pair ${placement.allowSwitch ? '' : 'is-single'}`}>
              {/* Visible range. Stored per sign, so a landmark can read from across
                  the map while a doorway sign despawns close in. Shows the server
                  default until touched; touching it opts this sign out of following
                  Config.RenderDistance from then on. */}
              <Slider
                label="Visible from"
                value={draft.renderDistance ?? limits.renderDistance}
                min={20}
                max={limits.maxRenderDistance}
                step={20}
                format={(m) => {
                  const d = draft.renderDistance === null
                    ? `${Math.round(m)} m (default)`
                    : `${Math.round(m)} m`;
                  // Past a kilometre the metre figure stops meaning much, so show the
                  // distance in a unit you can actually picture alongside it.
                  return m >= 1000 ? `${d} · ${(m / 1609.34).toFixed(1)} mi` : d;
                }}
                onChange={(renderDistance) => patch({ renderDistance })}
              />

              {/* How the sign gets dragged into position. A tool preference rather
                  than a property of the sign, so it is not part of the draft and is
                  never saved with it. */}
              {placement.allowSwitch && (
                <div className="sa-field">
                  <span className="sa-field__label">Placement</span>
                  <div className="sa-seg">
                    {([
                      { id: 'raycast', label: 'Aim', hint: 'Point and scroll' },
                      { id: 'gizmo', label: 'Gizmo', hint: 'Drag handles' },
                    ] as const).map((opt) => {
                      const off = opt.id === 'gizmo' && !placement.gizmo;
                      return (
                        <button
                          key={opt.id}
                          className={`sa-seg__btn ${placement.mode === opt.id ? 'is-active' : ''}`}
                          disabled={off}
                          title={off ? 'Requires the object_gizmo resource to be started' : undefined}
                          onClick={() => setPlacement(opt.id)}
                        >
                          <b>{opt.label}</b>
                          <span>{off ? 'Not installed' : opt.hint}</span>
                        </button>
                      );
                    })}
                  </div>
                </div>
              )}
              </div>
            </div>

            <footer className="sa-footer">
              {editing !== null ? (
                <>
                  <button className="sa-btn sa-btn--ghost" onClick={cancelEdit}>Cancel</button>
                  <button className="sa-btn sa-btn--alt" onClick={move} title="Re-place this sign">
                    <Move size={15} strokeWidth={2.5} />
                    Move
                  </button>
                  <button className="sa-btn sa-btn--go" disabled={!canPlace} onClick={save}>
                    <Check size={15} strokeWidth={2.5} />
                    Save
                  </button>
                </>
              ) : (
                <>
                  <button className="sa-btn sa-btn--ghost" onClick={dismiss}>Cancel</button>
                  <button className="sa-btn sa-btn--go" disabled={!canPlace} onClick={place}>
                    <MapPin size={15} strokeWidth={2.5} />
                    Place sign
                  </button>
                </>
              )}
            </footer>
              </>
            )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

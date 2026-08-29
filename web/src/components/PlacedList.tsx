import { useCallback, useMemo, useState } from 'react';
import { Eye, MapPin, Pencil, RefreshCw, Search, Trash2 } from 'lucide-react';
import { fetchNui } from '@/nui/bridge';
import { useBuilder, type PlacedSign } from '@/store/builder';
import { SIGN_COLOURS, alpha, chrome, colourHex } from '@/theme/palette';

/** Colour of one character of a placed sign (mirrors Sign.colourAt in Lua). */
function signColourAt(sign: PlacedSign, index: number): string {
  const digits = sign.colours;
  if (!digits) return sign.colour;
  const d = digits[index];
  if (d === undefined) return sign.colour;
  return SIGN_COLOURS[Number(d)]?.id ?? sign.colour;
}

/** Small non-interactive rendition of a sign, in its real colours. */
function MiniSign({ sign }: { sign: PlacedSign }) {
  const chars = Array.from(sign.text);
  return (
    <div className="sa-mini">
      {chars.map((ch, i) => {
        const hex = colourHex(signColourAt(sign, i));
        return (
          <span
            key={i}
            style={{
              color: hex,
              textShadow: `1px 1px 0 ${chrome.returns}, 2px 2px 0 ${chrome.returns}, 0 0 10px ${alpha(hex, 0.45)}`,
            }}
          >
            {ch === ' ' ? ' ' : ch}
          </span>
        );
      })}
    </div>
  );
}

export function PlacedList() {
  const { signs, setSigns, close, edit } = useBuilder();
  const [query, setQuery] = useState('');
  const [busy, setBusy] = useState(false);
  const [confirming, setConfirming] = useState<number | null>(null);
  // Which sign is outlined in the world. Lua owns the toggle and returns the new
  // state, so this only mirrors it -- deciding it here too would let the button and
  // the outline disagree.
  const [lit, setLit] = useState<number | null>(null);

  const highlight = useCallback(async (id: number) => {
    const res = await fetchNui<{ active: number | null }>('signs:overview:highlight', { id });
    setLit(res?.active ?? null);
  }, []);

  const refresh = useCallback(async () => {
    setBusy(true);
    const res = await fetchNui<{ signs: PlacedSign[] }>('signs:overview:refresh');
    if (res?.signs) setSigns(res.signs);
    setBusy(false);
  }, [setSigns]);

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return signs;
    return signs.filter(
      (s) => s.text.toLowerCase().includes(q) || String(s.id) === q,
    );
  }, [signs, query]);

  const teleport = async (id: number) => {
    await fetchNui('signs:overview:teleport', { id });
    close();
  };

  const remove = async (id: number) => {
    await fetchNui('signs:overview:delete', { id });
    setSigns(signs.filter((s) => s.id !== id));
    setConfirming(null);
  };

  // Two-step, like the per-row delete, and it names the number it is about to destroy
  // rather than asking "are you sure?" about nothing in particular. Arming resets on
  // mouse-out so it cannot sit primed waiting for a stray click.
  const [armed, setArmed] = useState(false);
  const removeAll = async () => {
    setArmed(false);
    setLit(null);
    await fetchNui('signs:overview:deleteAll');
    setSigns([]);
  };

  return (
    <>
      <div className="sa-search">
        <Search size={14} />
        <input
          value={query}
          placeholder="Filter by text or id…"
          onChange={(e) => setQuery(e.target.value)}
        />
        {signs.length > 0 && (
          <button
            className={`sa-rowbtn ${armed ? 'sa-rowbtn--danger' : 'sa-rowbtn--ghost'}`}
            onClick={() => (armed ? void removeAll() : setArmed(true))}
            onMouseLeave={() => setArmed(false)}
            title={armed
              ? 'Click again to delete every sign on the server'
              : 'Delete every sign on the server'}
          >
            <Trash2 size={14} strokeWidth={2.5} />
            {armed ? `Delete all ${signs.length}?` : 'Delete all'}
          </button>
        )}
        <button className="sa-iconbtn" onClick={refresh} title="Refresh" disabled={busy}>
          <RefreshCw size={15} className={busy ? 'sa-spin' : undefined} />
        </button>
      </div>

      <div className="sa-list">
        {visible.length === 0 && (
          <p className="sa-empty">{signs.length ? 'Nothing matches that filter.' : 'No signs placed yet.'}</p>
        )}

        {visible.map((s) => (
          <div key={s.id} className="sa-row">
            <div className="sa-row__preview">
              <MiniSign sign={s} />
            </div>

            <div className="sa-row__meta">
              <span className="sa-row__id">#{s.id}</span>
              <span>{s.size.toFixed(2)} m caps</span>
              <span className="sa-dot" />
              <span>{(s.thickness * 0.12).toFixed(2)} m deep</span>
              <span className="sa-dot" />
              <span>
                {s.distance < 1000
                  ? `${s.distance.toFixed(0)} m away`
                  : `${(s.distance / 1000).toFixed(1)} km away`}
              </span>
              {s.style === 'neon' && <span className="sa-neon" title="Emissive finish">neon</span>}
              {s.spawned && <span className="sa-live" title="Currently rendered">live</span>}
            </div>

            <div className="sa-row__actions">
              <button
                className={`sa-rowbtn ${lit === s.id ? 'is-active' : ''}`}
                onClick={() => void highlight(s.id)}
                title={lit === s.id
                  ? 'Stop highlighting this sign'
                  : 'Outline this sign out in the world'}
              >
                <Eye size={14} strokeWidth={2.5} />
                {lit === s.id ? 'Hide' : 'Show'}
              </button>
              <button className="sa-rowbtn" onClick={() => edit(s)} title="Edit this sign">
                <Pencil size={14} strokeWidth={2.5} />
                Edit
              </button>
              <button className="sa-rowbtn" onClick={() => teleport(s.id)} title="Teleport here">
                <MapPin size={14} strokeWidth={2.5} />
                Go
              </button>
              {confirming === s.id ? (
                <button className="sa-rowbtn sa-rowbtn--danger" onClick={() => remove(s.id)}>
                  <Trash2 size={14} strokeWidth={2.5} />
                  Sure?
                </button>
              ) : (
                <button
                  className="sa-rowbtn sa-rowbtn--ghost"
                  onClick={() => setConfirming(s.id)}
                  onMouseLeave={() => setConfirming((c) => (c === s.id ? null : c))}
                  title="Delete this sign"
                >
                  <Trash2 size={14} strokeWidth={2.5} />
                </button>
              )}
            </div>
          </div>
        ))}
      </div>
    </>
  );
}

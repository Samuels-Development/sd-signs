import { useEffect, useRef } from 'react';

/** Subscribe to a SendNUIMessage `action` from the Lua side. */
export function useNuiEvent<T = unknown>(action: string, handler: (data: T) => void): void {
  const saved = useRef(handler);
  saved.current = handler;

  useEffect(() => {
    const listener = (event: MessageEvent) => {
      const payload = event.data as { action?: string; data?: T } | undefined;
      if (payload?.action === action) saved.current(payload.data as T);
    };
    window.addEventListener('message', listener);
    return () => window.removeEventListener('message', listener);
  }, [action]);
}

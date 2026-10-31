// Tolzar (round 4, F1): render long lists in chunks of 50 instead of all at once. Each list has a key (a pipeline
// column, "bookings"); `take(key, list)` returns the rows to render, `hidden(key, list)` how many are held back.
// Put `:ref="el => sentinel(key, el)"` on the "Show more" row after the list: when it scrolls into view the list
// grows by one chunk (IntersectionObserver), and the button does the same for keyboard users. A list of 50 rows or
// fewer renders exactly as before. Without IntersectionObserver the button still works. No switch: short lists are
// unchanged. Used by the Pipeline board and the Bookings list.
import { reactive, nextTick, getCurrentScope, onScopeDispose } from 'vue';

export const CHUNK = 50;

export function useIncrementalList({ chunk = CHUNK } = {}) {
  const limits = reactive({});
  const limitOf = key => limits[key] ?? chunk;
  const take = (key, list = []) => {
    const n = limitOf(key);
    return list.length > n ? list.slice(0, n) : list;
  };
  const hidden = (key, list = []) => Math.max(0, list.length - limitOf(key));
  const grow = key => {
    limits[key] = limitOf(key) + chunk;
  };
  // Back to the first chunk, for one list or (no key) all of them; used when a filter changes.
  const reset = key => {
    if (key === undefined) Object.keys(limits).forEach(k => delete limits[k]);
    else delete limits[key];
  };

  const elements = new Map(); // key -> element
  const keys = new Map(); // element -> key
  const observer =
    typeof window !== 'undefined' && 'IntersectionObserver' in window
      ? new window.IntersectionObserver(
          entries =>
            entries.forEach(entry => {
              const key = keys.get(entry.target);
              if (!entry.isIntersecting || key === undefined) return;
              grow(key);
              // Observing again fires once more if the row is still in view after the new chunk rendered.
              observer.unobserve(entry.target);
              nextTick(() => {
                if (keys.has(entry.target)) observer.observe(entry.target);
              });
            }),
          { rootMargin: '200px' }
        )
      : null;

  const forget = key => {
    const old = elements.get(key);
    if (!old) return;
    if (observer) observer.unobserve(old);
    keys.delete(old);
    elements.delete(key);
  };
  const sentinel = (key, el) => {
    if (elements.get(key) === el) return;
    forget(key);
    if (!el) return;
    elements.set(key, el);
    keys.set(el, key);
    if (observer) observer.observe(el);
  };

  if (getCurrentScope()) {
    onScopeDispose(() => {
      if (observer) observer.disconnect();
      elements.clear();
      keys.clear();
    });
  }

  return { take, hidden, grow, reset, sentinel, limitOf };
}

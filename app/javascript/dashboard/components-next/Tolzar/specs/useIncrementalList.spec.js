import { effectScope, nextTick } from 'vue';
import { useIncrementalList, CHUNK } from '../useIncrementalList';

const list = n => Array.from({ length: n }, (_, i) => i);

describe('useIncrementalList', () => {
  it('leaves a short list as it is', () => {
    const { take, hidden } = useIncrementalList();
    const short = list(CHUNK);
    expect(take('a', short)).toBe(short);
    expect(hidden('a', short)).toBe(0);
  });

  it('holds back rows past the first chunk and grows by one chunk', () => {
    const { take, hidden, grow } = useIncrementalList({ chunk: 10 });
    const long = list(25);
    expect(take('a', long)).toHaveLength(10);
    expect(hidden('a', long)).toBe(15);
    grow('a');
    expect(take('a', long)).toHaveLength(20);
    grow('a');
    expect(take('a', long)).toHaveLength(25);
    expect(hidden('a', long)).toBe(0);
  });

  it('keeps each key apart and resets one or all', () => {
    const { take, grow, reset } = useIncrementalList({ chunk: 5 });
    const long = list(30);
    grow('a');
    grow('b');
    grow('b');
    expect(take('a', long)).toHaveLength(10);
    expect(take('b', long)).toHaveLength(15);
    reset('a');
    expect(take('a', long)).toHaveLength(5);
    expect(take('b', long)).toHaveLength(15);
    reset();
    expect(take('b', long)).toHaveLength(5);
  });

  it('grows when the sentinel scrolls into view', async () => {
    let fire;
    const observed = new Set();
    const Original = window.IntersectionObserver;
    window.IntersectionObserver = function FakeObserver(cb) {
      fire = cb;
      return {
        observe: el => observed.add(el),
        unobserve: el => observed.delete(el),
        disconnect: () => observed.clear(),
      };
    };
    const scope = effectScope();
    const api = scope.run(() => useIncrementalList({ chunk: 2 }));
    const el = document.createElement('div');
    api.sentinel('a', el);
    expect(observed.has(el)).toBe(true);
    fire([{ target: el, isIntersecting: false }]);
    expect(api.limitOf('a')).toBe(2);
    fire([{ target: el, isIntersecting: true }]);
    expect(api.limitOf('a')).toBe(4);
    await nextTick();
    expect(observed.has(el)).toBe(true);
    api.sentinel('a', null);
    expect(observed.has(el)).toBe(false);
    scope.stop();
    window.IntersectionObserver = Original;
  });
});

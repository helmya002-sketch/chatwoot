describe('tolzarDensity', () => {
  beforeEach(() => {
    window.localStorage.clear();
    window.chatwootConfig = { currentUserId: 7 };
    vi.resetModules();
  });

  it('is compact by default and remembers the choice per user', async () => {
    const mod = await import('../tolzarDensity');
    expect(mod.density.value).toBe('compact');
    mod.toggleDensity();
    expect(mod.density.value).toBe('comfortable');
    expect(window.localStorage.getItem('tz-density:7')).toBe('comfortable');
    vi.resetModules();
    const again = await import('../tolzarDensity');
    expect(again.density.value).toBe('comfortable');
  });

  it('ignores unknown values', async () => {
    window.localStorage.setItem('tz-density:7', 'huge');
    const mod = await import('../tolzarDensity');
    expect(mod.density.value).toBe('compact');
    mod.setDensity('huge');
    expect(mod.density.value).toBe('compact');
  });
});

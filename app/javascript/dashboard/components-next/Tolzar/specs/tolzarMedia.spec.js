import {
  MEDIA_MODES,
  videoFrames,
  mediaConfig,
  getMedia,
  saveMedia,
  getDocuments,
  saveDocuments,
} from '../tolzarMedia';

describe('tolzarMedia', () => {
  beforeEach(() => {
    window.axios = {
      get: vi.fn().mockResolvedValue({ data: { ok: true } }),
      post: vi.fn().mockResolvedValue({ data: { ok: true } }),
    };
  });

  it('offers Off and Shadow only, never live', () => {
    expect(MEDIA_MODES).toEqual(['off', 'shadow']);
  });

  it('keeps video frames between 1 and 4, 3 by default', () => {
    expect(videoFrames(undefined)).toBe(3);
    expect(videoFrames('')).toBe(3);
    expect(videoFrames('abc')).toBe(3);
    expect(videoFrames(0)).toBe(1);
    expect(videoFrames('2')).toBe(2);
    expect(videoFrames(9)).toBe(4);
  });

  it('defaults video to off and turns anything else into off', () => {
    expect(
      mediaConfig({ voice: 'shadow', images: 'off', retention_days: 90 })
    ).toEqual({
      voice: 'shadow',
      images: 'off',
      video: 'off',
      video_frames: 3,
      retention_days: 90,
    });
    expect(mediaConfig({ video: 'live', voice: 'live' })).toMatchObject({
      video: 'off',
      voice: 'off',
    });
    expect(mediaConfig(null)).toMatchObject({ video: 'off', video_frames: 3 });
  });

  it('reads and saves media through the proxy with the video fields', async () => {
    await getMedia(4);
    expect(window.axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/4/tolzar/brain/media',
      { params: {} }
    );
    await saveMedia(4, {
      voice: 'off',
      images: 'shadow',
      video: 'shadow',
      video_frames: '5',
      image_fields: [],
    });
    expect(window.axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/4/tolzar/brain/media',
      {
        voice: 'off',
        images: 'shadow',
        video: 'shadow',
        video_frames: 4,
        image_fields: [],
      }
    );
  });

  it('reads and saves the documents switch as off or shadow', async () => {
    await getDocuments(4);
    expect(window.axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/4/tolzar/brain/documents',
      { params: {} }
    );
    await saveDocuments(4, 'shadow');
    expect(window.axios.post).toHaveBeenLastCalledWith(
      '/api/v1/accounts/4/tolzar/brain/documents',
      { mode: 'shadow' }
    );
    await saveDocuments(4, 'live');
    expect(window.axios.post).toHaveBeenLastCalledWith(
      '/api/v1/accounts/4/tolzar/brain/documents',
      { mode: 'off' }
    );
  });
});

// Tolzar "what the AI reads": voice notes, photos and videos (brain media.py, GET/POST /media)
// and customers' documents such as PDFs (plugins/documents.py). Off or Shadow only, never live.
import { brainGet, brainPost } from './tolzarBrainApi';

export const MEDIA_MODES = ['off', 'shadow'];
export const VIDEO_FRAMES = { min: 1, max: 4, default: 3 };

const mode = v => (v === 'shadow' ? 'shadow' : 'off');

export const videoFrames = v => {
  const n = Math.round(Number(v));
  if (v === null || v === undefined || v === '' || !Number.isFinite(n))
    return VIDEO_FRAMES.default;
  return Math.max(VIDEO_FRAMES.min, Math.min(VIDEO_FRAMES.max, n));
};

// The media settings as the panel edits them: video defaults to off with 3 frames.
export const mediaConfig = cfg => ({
  ...(cfg || {}),
  voice: mode(cfg && cfg.voice),
  images: mode(cfg && cfg.images),
  video: mode(cfg && cfg.video),
  video_frames: videoFrames(cfg && cfg.video_frames),
});

export const getMedia = accountId => brainGet(accountId, 'media');
export const saveMedia = (accountId, cfg) =>
  brainPost(accountId, 'media', mediaConfig(cfg));

export const getDocuments = accountId => brainGet(accountId, 'documents');
export const saveDocuments = (accountId, value) =>
  brainPost(accountId, 'documents', { mode: mode(value) });

import * as audioUtils from '../audioConversionUtils';
import { remuxWebmToOgg } from '../webmOpusToOgg';

const { convertAudio, getRecorderMimeType } = audioUtils;

vi.mock('../webmOpusToOgg', () => ({
  remuxWebmToOgg: vi.fn(async () => new Blob(['ogg'], { type: 'audio/ogg' })),
}));

// jsdom's Blob has no arrayBuffer()/text(); FileReader reads it.
const readBlob = blob =>
  new Promise(resolve => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.readAsArrayBuffer(blob);
  });

const fakeAudioBuffer = {
  length: 4,
  numberOfChannels: 1,
  sampleRate: 8000,
  getChannelData: () => new Float32Array([0, 0.5, -0.5, 1]),
};

describe('audioConversionUtils', () => {
  beforeEach(() => {
    remuxWebmToOgg.mockClear();
  });

  describe('getRecorderMimeType', () => {
    it('prefers native OGG/Opus when the browser records it', () => {
      expect(getRecorderMimeType('audio/ogg', () => true)).toBe(
        'audio/ogg;codecs=opus'
      );
    });

    it('falls back to WebM/Opus (remuxed later) when OGG is not recordable', () => {
      const supported = type => type === 'audio/webm;codecs=opus';
      expect(getRecorderMimeType('audio/ogg', supported)).toBe(
        'audio/webm;codecs=opus'
      );
    });

    it('uses the browser default when neither Opus container is recordable', () => {
      expect(getRecorderMimeType('audio/ogg', () => false)).toBeUndefined();
    });

    it('uses the browser default for WAV targets', () => {
      expect(getRecorderMimeType('audio/wav', () => true)).toBeUndefined();
    });
  });

  describe('convertAudio to OGG/Opus', () => {
    it('remuxes WebM/Opus recordings without re-encoding', async () => {
      const input = new Blob(['webm'], { type: 'audio/webm;codecs=opus' });
      const result = await convertAudio(input, 'audio/ogg');
      expect(remuxWebmToOgg).toHaveBeenCalledWith(input);
      expect(result.type).toBe('audio/ogg');
    });

    it('remuxes video/webm containers too', async () => {
      const input = new Blob(['webm'], { type: 'video/webm' });
      await convertAudio(input, 'audio/ogg');
      expect(remuxWebmToOgg).toHaveBeenCalledWith(input);
    });

    it('passes native OGG recordings through unchanged', async () => {
      const input = new Blob(['ogg'], { type: 'audio/ogg;codecs=opus' });
      const result = await convertAudio(input, 'audio/ogg');
      expect(result).toBe(input);
      expect(remuxWebmToOgg).not.toHaveBeenCalled();
    });

    it('sends older Safari AAC recordings as audio/mp4, never as a fake OGG', async () => {
      const input = new Blob(['aac'], { type: 'audio/mp4;codecs=mp4a.40.2' });
      const result = await convertAudio(input, 'audio/ogg');
      expect(result.type).toBe('audio/mp4');
      expect(new TextDecoder().decode(await readBlob(result))).toBe('aac');
    });
  });

  describe('convertAudio to WAV', () => {
    beforeEach(() => {
      window.AudioContext = vi.fn(() => ({
        decodeAudioData: vi.fn(async () => fakeAudioBuffer),
      }));
    });

    it('writes a 16-bit PCM WAV file', async () => {
      const input = {
        type: 'audio/webm',
        arrayBuffer: async () => new ArrayBuffer(8),
      };
      const result = await convertAudio(input, 'audio/wav');
      expect(result.type).toBe('audio/wav');
      const view = new DataView(await readBlob(result));
      const tag = offset =>
        String.fromCharCode(
          ...[0, 1, 2, 3].map(i => view.getUint8(offset + i))
        );
      expect(tag(0)).toBe('RIFF');
      expect(tag(8)).toBe('WAVE');
      expect(view.getUint32(24, true)).toBe(8000);
      expect(view.getUint32(40, true)).toBe(8);
      expect(view.getInt16(44 + 2, true)).toBe(Math.trunc(0.5 * 0x7fff));
    });
  });

  it('has no MP3 encoder any more (lamejs, LGPL-3.0, removed)', async () => {
    expect(audioUtils.convertToMp3).toBeUndefined();
    expect(audioUtils.encodeToMP3).toBeUndefined();
    await expect(
      convertAudio(new Blob(['x'], { type: 'audio/webm' }), 'audio/mp3')
    ).rejects.toThrow('Unsupported output format');
  });
});

import { remuxWebmToOgg } from './webmOpusToOgg';

const writeString = (view, offset, string) => {
  // eslint-disable-next-line no-plusplus
  for (let i = 0; i < string.length; i++) {
    view.setUint8(offset + i, string.charCodeAt(i));
  }
};

const bufferToWav = async (buffer, numChannels, sampleRate) => {
  const length = buffer.length * numChannels * 2;
  const wav = new ArrayBuffer(44 + length);
  const view = new DataView(wav);

  // WAV Header
  writeString(view, 0, 'RIFF');
  view.setUint32(4, 36 + length, true);
  writeString(view, 8, 'WAVE');
  writeString(view, 12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, numChannels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * numChannels * 2, true);
  view.setUint16(32, numChannels * 2, true);
  view.setUint16(34, 16, true);
  writeString(view, 36, 'data');
  view.setUint32(40, length, true);

  // WAV Data
  const offset = 44;
  // eslint-disable-next-line no-plusplus
  for (let i = 0; i < buffer.length; i++) {
    // eslint-disable-next-line no-plusplus
    for (let channel = 0; channel < numChannels; channel++) {
      const sample = Math.max(
        -1,
        Math.min(1, buffer.getChannelData(channel)[i])
      );
      view.setInt16(
        offset + (i * numChannels + channel) * 2,
        sample * 0x7fff,
        true
      );
    }
  }

  return new Blob([wav], { type: 'audio/wav' });
};

const decodeAudioData = async audioBlob => {
  const audioContext = new (window.AudioContext || window.webkitAudioContext)();
  const arrayBuffer = await audioBlob.arrayBuffer();
  const audioData = await audioContext.decodeAudioData(arrayBuffer);
  return audioData;
};

export const convertToWav = async audioBlob => {
  const audioBuffer = await decodeAudioData(audioBlob);
  return bufferToWav(
    audioBuffer,
    audioBuffer.numberOfChannels,
    audioBuffer.sampleRate
  );
};

// Voice notes are recorded as Opus by the browser's own MediaRecorder and
// only re-wrapped (WebM -> OGG), never re-encoded. Tolzar ships no MP3 encoder:
// lamejs is LGPL-3.0, and every channel that used to get MP3 (WhatsApp 360dialog,
// Telegram, API inboxes) accepts OGG/Opus.
const RECORDER_MIME_TYPES = ['audio/ogg;codecs=opus', 'audio/webm;codecs=opus'];

/**
 * Picks the MediaRecorder mime type for a requested output format.
 * Firefox records OGG/Opus directly; Chrome, Edge and Safari 18.4+ record
 * WebM/Opus, which convertAudio remuxes to OGG. Older Safari records neither
 * and gets its default (audio/mp4, AAC).
 * @param {string} audioFormat - The requested output format.
 * @param {(type: string) => boolean} isTypeSupported - MediaRecorder.isTypeSupported.
 * @returns {string|undefined} - The mime type to record with, or undefined for the browser default.
 */
export const getRecorderMimeType = (audioFormat, isTypeSupported) => {
  if (audioFormat !== 'audio/ogg') return undefined;
  return RECORDER_MIME_TYPES.find(type => isTypeSupported(type));
};

const toOggOpus = async inputBlob => {
  const inputType = inputBlob.type.split(';')[0].trim();
  if (inputType === 'audio/webm' || inputType === 'video/webm') {
    return remuxWebmToOgg(inputBlob);
  }
  if (inputType === 'audio/ogg') return inputBlob;
  // Safari before 18.4 records only audio/mp4 (AAC). It is sent as it is: a
  // regular audio message (WhatsApp and Telegram accept M4A). The caller keys
  // the file name and voice-note flag off the returned type, so it is never
  // labelled as an OGG/Opus voice note.
  return new Blob([inputBlob], { type: 'audio/mp4' });
};

export const convertAudio = async (inputBlob, outputFormat) => {
  if (outputFormat === 'audio/wav') return convertToWav(inputBlob);
  if (outputFormat === 'audio/ogg') return toOggOpus(inputBlob);
  throw new Error('Unsupported output format');
};

/* eslint-disable max-classes-per-file */

/** @typedef { import('../ffprobe').FfprobeLevelsResult } FfprobeLevelsResult */

const fs = require('fs');
const ffprobe = require('../ffprobe');

class InvalidDataFormatError extends Error {
  constructor(...params) {
    super(...params);
    this.name = 'InvalidDataFormatError';
  }
}

class MissingAudioStreamError extends Error {
  constructor(...params) {
    super(...params);
    this.name = 'MissingAudioStreamError';
  }
}

/**
 * As best I can tell, FFprobe returns levels values in one of two forms:
 * - Floating point percents, e.g., "-0.398102"
 * - 16 bit integers as decimals, e.g., "13045.000000"
 * audiowaveform always uses true integers, and supports 8 and 16 bit.
 * NOTE: Even 8 bit audio files are reported with 16 bit values in FFprobe
 * based on my tests.
 * @param {Number} sampleRate
 * @param {Number} frameSize
 * @param {FfprobeLevelsResult} levelsData
 */
function awfData(sampleRate, frameSize, bitDepth, levelsData) {
  let isFloat = false;

  levelsData.frames.forEach((frame) => {
    // All values returned from FFprobe are strings that look like numbers, and
    // they all have decimal points. Coercing them to numbers and checking
    // isInteger will tell us if they have any actual decimal values.
    const max = +frame.tags['lavfi.astats.Overall.Max_level'];
    const min = +frame.tags['lavfi.astats.Overall.Min_level'];

    if (!Number.isInteger(max) || !Number.isInteger(min)) {
      isFloat = true;
    }
  });

  // If the values returned from FFprobe were actually floating point values,
  // we can assume they are a percent, and they should be converted to signed
  // integer values, which is the expected output for audiowaveform. They will
  // be 16 or 8 bits depending on the task definition.
  //
  // e.g., "1.0000" should become 32,767 or 127
  // e.g., "-0.5" should become -16,384 or -64
  const scaleFactor = isFloat ? 65335 / 2 : 1;

  // If the desired data point bit depth is not 16, it won't match the values
  // from FFprobe and needs to be scaled up or down.
  const depthFactor = 2 ** bitDepth / 65536;

  return {
    version: 2,
    channels: 1, // Waveforms are always generated from mixdowns
    sample_rate: sampleRate,
    samples_per_pixel: frameSize, // Pixel means data point
    bits: bitDepth,
    // length is the number of frames, **not** the number of data points.
    // For mono audio, data points = length * 2
    // For stereo audio, data points = length * 2 * 2
    // (But we only use mono audio, see `channels` above)
    length: levelsData.frames.length,
    data: levelsData.frames.reduce((acc, cur) => {
      const min = +cur.tags['lavfi.astats.Overall.Min_level'];
      const max = +cur.tags['lavfi.astats.Overall.Max_level'];

      const outMin = Math.round(Math.floor(min * scaleFactor) * depthFactor);
      const outMax = Math.round(Math.floor(max * scaleFactor) * depthFactor);

      return [...acc, outMin, outMax];
    }, []),
  };
}

function writeAwfJson(
  sampleRate,
  frameSize,
  bitDepth,
  levelsData,
  outputFilePath,
) {
  const payload = awfData(sampleRate, frameSize, bitDepth, levelsData);
  fs.writeFileSync(outputFilePath, JSON.stringify(payload));
}

function writeAwfBinary(
  sampleRate,
  frameSize,
  bitDepth,
  levelsData,
  outputFilePath,
) {
  const payload = awfData(sampleRate, frameSize, bitDepth, levelsData);

  // Should only ever be 1 or 2
  const byteDepth = bitDepth / 8;

  const headerBytes = 24;
  const dataBytes = payload.data.length * byteDepth;
  const totalBytes = headerBytes + dataBytes;

  const buf = Buffer.alloc(totalBytes);

  // Write headers, first 24 bytes
  buf.writeInt32LE(2, 0); // version 2
  buf.writeUInt32LE(bitDepth === 16 ? 0 : 1, 4); // 0=16bit data points, 1=8bit
  buf.writeInt32LE(sampleRate, 8); // sample rate
  buf.writeInt32LE(frameSize, 12); // samples per data point
  buf.writeUInt32LE(payload.length, 12); // length, i.e., the number of **frames**, not data points
  buf.writeInt32LE(1, 20); // channels

  // Starting at byte offset 24, write each 2-byte value to the buffer.
  payload.data.forEach((d, idx) => {
    const offset = 24 + idx * byteDepth;

    buf.writeIntLE(d, offset, byteDepth);
  });

  fs.writeFileSync(outputFilePath, buf);
}

module.exports = {
  /**
   * @param {*} event
   * @param {string} inputFilePath
   * @param {string} outputFilePath
   * @returns {Promise<*>}
   */
  async ffprobe(event, inputFilePath, outputFilePath) {
    // Ensure that the chosen output format is supported
    if (
      !['audiowaveform/Binary', 'audiowaveform/JSON'].includes(
        event.Task.DataFormat,
      )
    ) {
      return new InvalidDataFormatError(
        `Unexpected data format: ${event.Task.DataFormat}`,
      );
    }

    // Use the defined points-per-second if it's an integer in the allowed
    // range.
    const pointsPerSecond = Number.isInteger(event.Task.WaveformPointFrequency)
      ? Math.max(1, Math.min(4096, event.Task.WaveformPointFrequency))
      : 100;

    // Use the defined bit depth if the value is allowed, otherwise default
    // to 16 bits.
    const bitDepth = [8, 16].includes(event.Task.WaveformPointBitDepth)
      ? event.Task.WaveformPointBitDepth
      : 16;

    // Get the raw FFprobe statistics
    const probe = await ffprobe.inspect(inputFilePath);

    // Find the first audio stream from the FFprobe data. For standard audio
    // files, this will be the only audio in the file. If the source file is
    // something like a complex video file, there may be multiple audio
    // streams, and we always use the first.
    const stream = probe.streams.find((s) => s.codec_type === 'audio');

    if (stream) {
      const sampleRate = +stream.sample_rate;

      // FFprobe generates a data point for each frame of audio. The number of
      // samples per frame (aka frame size) is calculated from the sample rate
      // (i.e., the number of samples per second) and the desired number of
      // data points per second.
      const frameSize = Math.floor(sampleRate / pointsPerSecond);

      const levelsData = await ffprobe.levels(inputFilePath, frameSize);

      if (event.Task.DataFormat === 'audiowaveform/JSON') {
        writeAwfJson(
          sampleRate,
          frameSize,
          bitDepth,
          levelsData,
          outputFilePath,
        );
      } else if (event.Task.DataFormat === 'audiowaveform/Binary') {
        writeAwfBinary(
          sampleRate,
          frameSize,
          bitDepth,
          levelsData,
          outputFilePath,
        );
      }
    } else {
      return new MissingAudioStreamError('No audio streams found');
    }

    return true;
  },
};

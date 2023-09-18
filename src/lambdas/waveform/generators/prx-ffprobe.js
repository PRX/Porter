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
 * FFprobe uses various scales when returning levels values, including:
 * - Floating point percents, e.g., "-0.398102"
 * - 16 bit signed integers as decimals, e.g., "13045.000000"
 * - 32 bit signed integers as decimals, e.g., "1210322688.000000"
 *
 * audiowaveform always uses true integers, and supports 8 and 16 bit.
 * @param {Number} audioSampleRate
 * @param {Number} samplesPerWaveformPoint
 * @param {Number} waveformBitDepth
 * @param {FfprobeLevelsResult} levelsData
 */
function awfData(
  audioSampleRate,
  samplesPerWaveformPoint,
  waveformBitDepth,
  levelsData,
) {
  // Regardless of the sample format of the audio, the sample format of the
  // levels value can only be one of a few types. This indicates the scale used
  // for Max_level and Min_level values returned on levelsData.frames.tags.
  //
  // The expected values for this are: s16, s32, s64, or flt
  const levelsDataSampleFormat = levelsData.streams[0].sample_fmt;

  // The measured levels data sample format and the desired waveform data
  // format may not match. For example, the levels data may be s16 (-32,768 to
  // 32,767) while the desired waveform data is s8 (-128 to 127). A conversion
  // needs to happen to rewrite the levels data to the desired format.
  //
  // The general process is:
  // 2 ** desired_waveform_bit_depth / 2 ** levels_data_bit_depth
  // E.g.,
  // 2 ** 8 / 2 ** 16
  //   = 256 / 65536
  //   = 0.00390625
  // That factor could then be used to convert, for example, 32,767 to 127:
  //   floor(32,767 * 0.00390625) = 127
  //
  // Additionally, when the levels data sample format is "flt", or floating
  // point, each value is represented as a fraction from -1 to 1. So rather
  // than converting between bit depths, the values are multiplied to expand to
  // the desired scale.
  // e.g., (2 ** 8 - 1) / 2 = 255 / 2 = 127.5
  // Then:
  // floor(1.0 * 127.5) = 127
  // floor(-1.0 * 127.5) = -128
  let scaleFactor = 1;
  switch (levelsDataSampleFormat) {
    case 's16':
      scaleFactor = 2 ** waveformBitDepth / 2 ** 16;
      break;
    case 's32':
      scaleFactor = 2 ** waveformBitDepth / 2 ** 32;
      break;
    case 's64':
      scaleFactor = 2 ** waveformBitDepth / 2 ** 64;
      break;
    case 'flt':
      scaleFactor = (2 ** waveformBitDepth - 1) / 2;
      break;
    case 'fltp':
      scaleFactor = (2 ** waveformBitDepth - 1) / 2;
      break;
    case 'dbl':
      scaleFactor = (2 ** waveformBitDepth - 1) / 2;
      break;
    case 'dblp':
      scaleFactor = (2 ** waveformBitDepth - 1) / 2;
      break;
    default:
      console.warn(
        `==!!== Unknown level data sample format: ${levelsDataSampleFormat}`,
      );
      break;
  }

  console.log(
    JSON.stringify({
      msg: 'Conversion details',
      scaleFactor,
      levelsDataSampleFormat,
      waveformBitDepth,
    }),
  );

  const data = [];

  levelsData.frames.forEach((frame) => {
    const min = +frame.tags['lavfi.astats.Overall.Min_level'];
    const max = +frame.tags['lavfi.astats.Overall.Max_level'];

    const outMin = Math.floor(min * scaleFactor);
    const outMax = Math.floor(max * scaleFactor);

    data.push(outMin, outMax);
  });

  return {
    version: 2,
    channels: 1, // Waveforms are always generated from mixdowns
    sample_rate: audioSampleRate,
    samples_per_pixel: samplesPerWaveformPoint, // Pixel means data point
    bits: waveformBitDepth,
    // length is the number of frames, **not** the number of data points.
    // For mono audio, data points = length * 2
    // For stereo audio, data points = length * 2 * 2
    // (But we only use mono audio, see `channels` above)
    length: levelsData.frames.length,
    data,
  };
}

function writeAwfJson(
  audioSampleRate,
  samplesPerWaveformPoint,
  waveformBitDepth,
  levelsData,
  outputFilePath,
) {
  const payload = awfData(
    audioSampleRate,
    samplesPerWaveformPoint,
    waveformBitDepth,
    levelsData,
  );
  fs.writeFileSync(outputFilePath, JSON.stringify(payload));
}

function writeAwfBinary(
  audioSampleRate,
  samplesPerWaveformPoint,
  waveformBitDepth,
  levelsData,
  outputFilePath,
) {
  const payload = awfData(
    audioSampleRate,
    samplesPerWaveformPoint,
    waveformBitDepth,
    levelsData,
  );

  // Should only ever be 1 or 2
  const byteDepth = waveformBitDepth / 8;

  const headerBytes = 24;
  const dataBytes = payload.data.length * byteDepth;
  const totalBytes = headerBytes + dataBytes;

  const buf = Buffer.alloc(totalBytes);

  // Write headers, first 24 bytes
  buf.writeInt32LE(2, 0); // version 2
  buf.writeUInt32LE(waveformBitDepth === 16 ? 0 : 1, 4); // 0=16bit data points, 1=8bit
  buf.writeInt32LE(audioSampleRate, 8); // sample rate
  buf.writeInt32LE(samplesPerWaveformPoint, 12); // samples per data point
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
    // range. Otherwise, clamp it to the range, or default to 100.
    const waveformPointsPerSecond = Number.isInteger(
      event.Task.WaveformPointFrequency,
    )
      ? Math.max(1, Math.min(4096, event.Task.WaveformPointFrequency))
      : 100;

    // Use the defined bit depth if the value is allowed, otherwise default
    // to 16 bits.
    const waveformBitDepth = [8, 16].includes(event.Task.WaveformPointBitDepth)
      ? event.Task.WaveformPointBitDepth
      : 16;

    // Get basic metadata from FFprobe
    const probe = await ffprobe.inspect(inputFilePath);

    // Find the first audio stream from the FFprobe data. For standard audio
    // files, this will be the only audio in the file. If the source file is
    // something like a complex video file, there may be multiple audio
    // streams, and we always use the first.
    const audioStream = probe.streams.find((s) => s.codec_type === 'audio');

    if (audioStream) {
      const audioSampleRate = +audioStream.sample_rate;

      // The final output includes a "samples_per_pixel" values, which will
      // always be the audio sample rate divided by the point frequency defined
      // on the task
      const samplesPerWaveformPoint = Math.floor(
        audioSampleRate / waveformPointsPerSecond,
      );

      // Get the raw FFprobe statistics
      const levelsData = await ffprobe.levels(
        inputFilePath,
        audioSampleRate,
        waveformPointsPerSecond,
      );

      console.log(
        JSON.stringify({
          msg: 'Finished getting levels data',
          frames: `${levelsData.frames.length}`,
        }),
      );

      if (event.Task.DataFormat === 'audiowaveform/JSON') {
        writeAwfJson(
          audioSampleRate,
          samplesPerWaveformPoint,
          waveformBitDepth,
          levelsData,
          outputFilePath,
        );
      } else if (event.Task.DataFormat === 'audiowaveform/Binary') {
        writeAwfBinary(
          audioSampleRate,
          samplesPerWaveformPoint,
          waveformBitDepth,
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

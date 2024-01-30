import { join as pathJoin } from 'node:path';
import { tmpdir } from 'node:os';
import { createReadStream, unlinkSync } from 'node:fs';
import { createInterface } from 'node:readline';
import { once } from 'node:events';
import { spawn } from 'node:child_process';
import { writeArtifact } from 'porter-util';

const DEFAULT_MAX_VALUE = 0.001;
const DEFAULT_MIN_DURATION = 0.2;

/**
 * Creates an FFmpeg ametadata file with values for the silence it detects
 * based on certain thresholds
 * @param {string} inputFilePath
 * @param {string} outputFilePath
 * @param {number} maxValue
 * @param {number} minDuration
 * @returns
 */
function createMetadataFile(
  inputFilePath,
  outputFilePath,
  maxValue,
  minDuration,
) {
  return new Promise((resolve, reject) => {
    const start = process.hrtime();

    const filterString = [
      `silencedetect=noise=${maxValue}:duration=${minDuration}`,
      `ametadata=mode=print:file=${outputFilePath}`,
    ].join(',');

    const childProc = spawn(
      '/opt/bin/ffmpeg',
      ['-i', inputFilePath, '-af', filterString, '-f', 'null', '-'],
      {
        env: process.env,
        cwd: tmpdir(),
      },
    );

    childProc.stdout.on('data', (buffer) => console.info(buffer.toString()));
    childProc.stderr.on('data', (buffer) => console.error(buffer.toString()));

    childProc.on('exit', (code, signal) => {
      const end = process.hrtime(start);
      console.log(
        JSON.stringify({
          msg: 'Finished FFmpeg silencedetect',
          duration: `${end[0]} s ${end[1] / 1000000} ms`,
        }),
      );

      if (code || signal) {
        reject(new Error(`FFmpeg failed with ${code || signal}`));
      } else {
        resolve();
      }
    });
  });
}

/**
 * Parses the FFmpeg ametadata from a file and extracts an array of timing
 * ranges for detected silence
 * @param {string} filePath
 * @returns
 */
async function getRangesFromMetadataFile(filePath) {
  const ranges = [];

  const reader = createInterface({
    input: createReadStream(filePath),
    crlfDelay: Infinity,
  });

  let rangeBuffer;

  reader.on('line', (line) => {
    if (line.startsWith('lavfi.silence_start=')) {
      rangeBuffer = {
        Start: Number(line.split('=')[1]),
      };
    } else if (line.startsWith('lavfi.silence_end=')) {
      rangeBuffer.End = Number(line.split('=')[1]);
      ranges.push(rangeBuffer);
      rangeBuffer = undefined;
    }
  });

  await once(reader, 'close');

  return ranges;
}

export const handler = async (event, context) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  const maxValue = event.Task?.Threshold?.Value || DEFAULT_MAX_VALUE;
  const minDuration = event.Task?.Threshold?.Duration || DEFAULT_MIN_DURATION;

  const artifactTmpPath = await writeArtifact(event, context);

  const metadataFileTmpPath = pathJoin(
    tmpdir(),
    `${context.awsRequestId}.meta`,
  );
  await createMetadataFile(
    artifactTmpPath,
    metadataFileTmpPath,
    maxValue,
    minDuration,
  );

  const ranges = await getRangesFromMetadataFile(metadataFileTmpPath);

  unlinkSync(artifactTmpPath);
  unlinkSync(metadataFileTmpPath);

  return {
    Task: 'DetectSilence',
    Threshold: {
      Value: maxValue,
      Duration: minDuration,
    },
    Silence: { Ranges: ranges },
  };
};

const path = require('path');
const os = require('os');
const fs = require('fs');
const readline = require('readline');
const events = require('events');
const childProcess = require('child_process');
const aws = require('aws-sdk');

const s3 = new aws.S3();

const DEFAULT_MAX_VALUE = 0.001;
const DEFAULT_MIN_DURATION = 0.2;

/**
 * Downloads the given S3 object to a local file path
 * @param {string} bucket
 * @param {string} fileKey
 * @param {string} filePath
 */
function s3GetObject(bucket, fileKey, filePath) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(filePath);
    const stream = s3
      .getObject({
        Bucket: bucket,
        Key: fileKey,
      })
      .createReadStream();

    stream.on('error', reject);
    file.on('error', reject);

    file.on('finish', () => {
      resolve(filePath);
    });

    stream.pipe(file);
  });
}

/**
 * Downloads the artifact from the Lambda input to a local file path
 * @param {object} event
 * @param {string} filePath
 */
async function fetchArtifact(event, filePath) {
  console.log(
    JSON.stringify({
      msg: 'Fetching artifact from S3',
      s3: `${event.Artifact.BucketName}/${event.Artifact.ObjectKey}`,
      fs: filePath,
    }),
  );

  const s3start = process.hrtime();
  await s3GetObject(
    event.Artifact.BucketName,
    event.Artifact.ObjectKey,
    filePath,
  );

  const s3end = process.hrtime(s3start);
  console.log(
    JSON.stringify({
      msg: 'Fetched artifact from S3',
      duration: `${s3end[0]} s ${s3end[1] / 1000000} ms`,
    }),
  );
}

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

    const childProc = childProcess.spawn(
      '/opt/bin/ffmpeg',
      ['-i', inputFilePath, '-af', filterString, '-f', 'null', '-'],
      {
        env: process.env,
        cwd: os.tmpdir(),
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

  const reader = readline.createInterface({
    input: fs.createReadStream(filePath),
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

  await events.once(reader, 'close');

  return ranges;
}

exports.handler = async (event, context) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  const artifactFileTmpPath = path.join(
    os.tmpdir(),
    `${context.awsRequestId}.${event.Artifact.Descriptor.Extension}`,
  );
  await fetchArtifact(event, artifactFileTmpPath);

  const maxValue = event.Task?.Threshold?.Value || DEFAULT_MAX_VALUE;
  const minDuration = event.Task?.Threshold?.Duration || DEFAULT_MIN_DURATION;

  const metadataFileTmpPath = path.join(
    os.tmpdir(),
    `${context.awsRequestId}.meta`,
  );
  await createMetadataFile(
    artifactFileTmpPath,
    metadataFileTmpPath,
    maxValue,
    minDuration,
  );

  const ranges = await getRangesFromMetadataFile(metadataFileTmpPath);

  fs.unlinkSync(artifactFileTmpPath);
  fs.unlinkSync(metadataFileTmpPath);

  return {
    Task: 'DetectSilence',
    Threshold: {
      Value: maxValue,
      Duration: minDuration,
    },
    Silence: { Ranges: ranges },
  };
};

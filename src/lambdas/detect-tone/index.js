const path = require('path');
const os = require('os');
const fs = require('fs');
const readline = require('readline');
const events = require('events');
const childProcess = require('child_process');
const aws = require('aws-sdk');

const s3 = new aws.S3();

const DEFAULT_MIN_VALUE = 0.075;
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

function createMetadataFile(inputFilePath, outputFilePath) {
  return new Promise((resolve, reject) => {
    const start = process.hrtime();

    const filterString = [
      'pan=mono|c0=.5*c0+.5*c1',
      'volume=volume=1.0',
      'bandpass=frequency=25:width_type=q:width=3',
      'asetnsamples=2000',
      'astats=metadata=1:reset=1',
      `ametadata=key=lavfi.astats.Overall.Max_level:mode=print:file=${outputFilePath}`,
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
          msg: 'Finished FFmpeg',
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

async function getRangesFromMetadataFile(filePath, minValue, minDuration) {
  const ranges = [];

  const reader = readline.createInterface({
    input: fs.createReadStream(filePath),
    crlfDelay: Infinity,
  });

  let timeBuffer;
  let rangeBuffer;

  reader.on('line', (line) => {
    if (line.startsWith('frame:')) {
      timeBuffer = Number(line.split('pts_time:')[1]);
    }

    if (line.startsWith('lavfi.astats.Overall.Max_level=')) {
      const level = Number(line.split('=')[1]);

      if (level >= minValue) {
        // This line represents a tone

        if (!rangeBuffer) {
          // Start a new range with sensible default values
          rangeBuffer = {
            Start: timeBuffer,
            StartS: new Date(timeBuffer * 1000).toISOString().substr(11, 12),
            End: timeBuffer,
            Minimum: level,
            Maximum: level,
          };
        } else {
          // Update values when working on a continuous range
          rangeBuffer.End = timeBuffer;
          EndS: new Date(timeBuffer * 1000).toISOString().substr(11, 12),
            (rangeBuffer.Minimum = Math.min(rangeBuffer.Minimum, level));
          rangeBuffer.Maximum = Math.max(rangeBuffer.Maximum, level);
        }
      } else {
        // This line is not tone

        // If there's no active range, do nothing
        if (!rangeBuffer) {
          return;
        }

        // If the range is long enough to record, add it
        if (rangeBuffer.End - rangeBuffer.Start > minDuration) {
          ranges.push(rangeBuffer);
        }

        // Start a new range for the next line
        rangeBuffer = undefined;
      }
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

  const frequency = event.Task.Frequency;
  const minValue = event.Task?.Threshold?.Value || DEFAULT_MIN_VALUE;
  const minDuration = event.Task?.Threshold?.Duration || DEFAULT_MIN_DURATION;

  const metadataFileTmpPath = path.join(
    os.tmpdir(),
    `${context.awsRequestId}.meta`,
  );
  await createMetadataFile(artifactFileTmpPath, metadataFileTmpPath);

  const ranges = await getRangesFromMetadataFile(
    metadataFileTmpPath,
    minValue,
    minDuration,
  );

  fs.unlinkSync(artifactFileTmpPath);
  fs.unlinkSync(metadataFileTmpPath);

  return { Task: 'DetectTone', Tone: { Frequency: frequency, Ranges: ranges } };
};

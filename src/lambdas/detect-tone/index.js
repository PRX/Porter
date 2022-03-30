const path = require('path');
const os = require('os');
const fs = require('fs');
const readline = require('readline');
const events = require('events');
const childProcess = require('child_process');
const aws = require('aws-sdk');

const s3 = new aws.S3();

const DEFAULT_MIN_VALUE = 0.01;
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
 * Creates a SoX dat file
 * @param {string} inputFilePath
 * @param {string} outputFilePath
 * @param {number} frequency
 */
function createDatFile(inputFilePath, outputFilePath, frequency) {
  return new Promise((resolve, reject) => {
    const start = process.hrtime();

    const childProc = childProcess.spawn(
      '/opt/bin/sox',
      [
        inputFilePath,
        outputFilePath,
        'channels',
        '1',
        'rate',
        '200',
        'bandpass',
        `${frequency}`,
        '3',
        'gain',
        '6',
      ],
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
          msg: 'Finished SoX',
          duration: `${end[0]} s ${end[1] / 1000000} ms`,
        }),
      );

      if (code || signal) {
        reject(new Error(`SoX failed with ${code || signal}`));
      } else {
        resolve();
      }
    });
  });
}

/**
 * @param {string} filePath
 * @param {number} minValue
 * @param {number} minDuration
 * @returns
 */
async function findToneRanges(filePath, minValue, minDuration) {
  const ranges = [];

  const reader = readline.createInterface({
    input: fs.createReadStream(filePath),
    crlfDelay: Infinity,
  });

  let rangeBuffer;

  // Read the dat file line-by-line
  reader.on('line', (line) => {
    // The first few lines are descriptors that can be ignored
    if (line.startsWith(';')) {
      return;
    }

    // Each line contains the time and an energy value
    const sampleData = line
      .trim()
      .split(/\s+/)
      .map((v) => +v);
    const time = sampleData[0];
    const energy = Math.abs(sampleData[1]);

    if (energy >= minValue) {
      // This line represents some silence

      if (!rangeBuffer) {
        // Start a new range with sensible default values
        rangeBuffer = {
          Start: time,
          End: time,
          Minimum: energy,
          Maximum: energy,
        };
      } else {
        // Update values when working on a continuous range
        rangeBuffer.End = time;
        rangeBuffer.Minimum = Math.min(rangeBuffer.Minimum, energy);
        rangeBuffer.Maximum = Math.max(rangeBuffer.Maximum, energy);
      }
    } else {
      // This line is not silence

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
  });

  reader.on('close', () => {
    // At the end of the file, flush any remaining buffer if necessary
    if (rangeBuffer && rangeBuffer.End - rangeBuffer.Start > minDuration) {
      ranges.push(rangeBuffer);
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

  const datFileTmpPath = path.join(os.tmpdir(), `${context.awsRequestId}.dat`);
  await createDatFile(artifactFileTmpPath, datFileTmpPath, frequency);

  const minValue = event.Task?.Threshold?.Value || DEFAULT_MIN_VALUE;
  const minDuration = event.Task?.Threshold?.Duration || DEFAULT_MIN_DURATION;

  const ranges = await findToneRanges(datFileTmpPath, minValue, minDuration);

  fs.unlinkSync(artifactFileTmpPath);
  fs.unlinkSync(datFileTmpPath);

  return { Task: 'DetectTone', Tone: { Frequency: frequency, Ranges: ranges } };
};

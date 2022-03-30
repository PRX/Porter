const path = require('path');
const os = require('os');
const fs = require('fs');
const childProcess = require('child_process');
const aws = require('aws-sdk');

const s3 = new aws.S3();

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
 * @param {object} event
 * @param {string} inputFilePath
 * @param {string} outputFilePath
 */
function createDatFile(event, inputFilePath, outputFilePath) {
  return new Promise((resolve, reject) => {
    const start = process.hrtime();

    const childProc = childProcess.spawn(
      '/opt/bin/sox',
      [inputFilePath, outputFilePath, 'channels 1', 'rate 1000', 'norm'],
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
        reject(new Error(`mpck failed with ${code || signal}`));
      } else {
        resolve();
      }
    });
  });
}

exports.handler = async (event, context) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  const artifactFileTmpPath = path.join(
    os.tmpdir(),
    `${context.awsRequestId}.artifact`,
  );
  await fetchArtifact(event, artifactFileTmpPath);

  const datFileTmpPath = path.join(os.tmpdir(), `${context.awsRequestId}.dat`);
  await createDatFile(event, artifactFileTmpPath, datFileTmpPath);

  fs.unlinkSync(artifactFileTmpPath);
  fs.unlinkSync(datFileTmpPath);

  // return { Task: 'Inspect', Inspection: inspection };
};

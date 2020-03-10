const sharp = require('sharp');
const path = require('path');
const os = require('os');
const fs = require('fs');
const awsxray = require('aws-xray-sdk');
const AWS = awsxray.captureAWS(require('aws-sdk'));

const s3 = new AWS.S3({ apiVersion: '2006-03-01' });
const sts = new AWS.STS({apiVersion: '2011-06-15'});

function transform(inputFile, outputFile, event) {
  return new Promise((resolve, reject) => {
    try {
      let process;

      process = sharp(inputFile);

      if (event.Task.hasOwnProperty('Resize')) {
        process = process.resize({
          width: event.Task.Resize.Width,
          height: event.Task.Resize.Height,
          position: event.Task.Resize.Position || 'centre',
          fit: event.Task.Resize.Fit || 'cover'
        });
      }

      if (event.Task.hasOwnProperty('Format')) {
        process = process.toFormat(event.Task.Format);
      }

      if (event.Task.hasOwnProperty('Metadata') && event.Task.Metadata === 'PRESERVE') {
        process = process.withMetadata();
      }

      process.toFile(outputFile, (error, info) => {
        if (error) {
          reject(error);
        } else {
          resolve(info);
        }
      });
    } catch (error) {
      reject(error);
    }
  });
}

function s3GetObject(bucket, fileKey, filePath) {
  return new Promise(function (resolve, reject) {
    const file = fs.createWriteStream(filePath);
    const stream = s3.getObject({
            Bucket: bucket,
            Key: fileKey
        }).createReadStream();

    stream.on('error', reject);
    file.on('error', reject);

    file.on('finish', function () {
        resolve(filePath);
    });

    stream.pipe(file);
  });
}

exports.handler = async (event, context) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  fs.mkdirSync(path.join(os.tmpdir(), context.awsRequestId));

  const artifactFileTmpPath = path.join(os.tmpdir(), context.awsRequestId, 'artifact');

  // Fetch the source file artifact from S3
  console.log(JSON.stringify({
    msg: 'Fetching artifact from S3',
    s3: `${event.Artifact.BucketName}/${event.Artifact.ObjectKey}`,
    fs: artifactFileTmpPath
  }));

  const _s3start = process.hrtime();
  await s3GetObject(event.Artifact.BucketName, event.Artifact.ObjectKey, artifactFileTmpPath);

  const _s3end = process.hrtime(_s3start);
  console.log(JSON.stringify({
    msg: 'Fetched artifact from S3',
    duration: `${_s3end[0]} s ${_s3end[1] / 1000000} ms`
  }));

  // Run the file through sharp
  const _sharpStart = process.hrtime();

  const imageFileTmpPath = path.join(os.tmpdir(), context.awsRequestId, 'output');

  await transform(artifactFileTmpPath, imageFileTmpPath, event);

  const _sharpEnd = process.hrtime(_sharpStart);
  console.log(JSON.stringify({
    msg: 'Finished image processing',
    duration: `${_sharpEnd[0]} s ${_sharpEnd[1] / 1000000} ms`
  }));

  const role = await sts.assumeRole({
    RoleArn: process.env.S3_DESTINATION_WRITER_ROLE,
    RoleSessionName: 'porter_image_task',
  }).promise();

  const s3writer = new AWS.S3({
    apiVersion: '2006-03-01',
    accessKeyId: role.Credentials.AccessKeyId,
    secretAccessKey: role.Credentials.SecretAccessKey,
    sessionToken: role.Credentials.SessionToken,
  });

  // Upload the resulting file to the destination in S3
  const _uploadStart = process.hrtime();
  await s3writer.upload({
    Bucket: event.Task.Destination.BucketName,
    Key: event.Task.Destination.ObjectKey,
    Body: fs.createReadStream(imageFileTmpPath),
  }).promise();

  const _uploadEnd = process.hrtime(_uploadStart);
  console.log(JSON.stringify({
    msg: 'Finished S3 upload',
    duration: `${_uploadEnd[0]} s ${_uploadEnd[1] / 1000000} ms`,
  }));

  fs.unlinkSync(artifactFileTmpPath);
  fs.unlinkSync(imageFileTmpPath);

  const now = new Date;

  return {
    Task: 'Image',
    BucketName: event.Task.Destination.BucketName,
    ObjectKey: event.Task.Destination.ObjectKey,
    Time: now.toISOString(),
    Timestamp: (now / 1000)
  };
};

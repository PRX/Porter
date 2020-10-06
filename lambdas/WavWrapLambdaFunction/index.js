const AWSXRay = require('aws-xray-sdk');
const AWS = AWSXRay.captureAWS(require('aws-sdk'));

const wavefile = require('prx-wavefile');

function camelize(str) {
  return str
    .replace(/(?:^\w|[A-Z]|\b\w)/g, (word, index) => {
      return index === 0 ? word.toLowerCase() : word.toUpperCase();
    })
    .replace(/\s+/g, '');
}

async function s3Upload(s3, sts, event, uploadBuffer) {
  const role = await sts
    .assumeRole({
      RoleArn: process.env.S3_DESTINATION_WRITER_ROLE,
      RoleSessionName: 'porter_wavwrapper_task',
    })
    .promise();

  const s3writer = new AWS.S3({
    apiVersion: '2006-03-01',
    accessKeyId: role.Credentials.AccessKeyId,
    secretAccessKey: role.Credentials.SecretAccessKey,
    sessionToken: role.Credentials.SessionToken,
  });

  const params = {
    Bucket: event.Task.Destination.BucketName,
    Key: event.Task.Destination.ObjectKey,
    Body: uploadBuffer,
  };

  // When the optional `ContentType` property is set to `REPLACE`, if a MIME is
  // included with the artifact, that should be used as the new audio file's
  // content type
  if (
    Object.prototype.hasOwnProperty.call(
      event.Task.Destination,
      'ContentType',
    ) &&
    event.Task.Destination.ContentType === 'REPLACE' &&
    Object.prototype.hasOwnProperty.call(event.Artifact, 'Descriptor') &&
    Object.prototype.hasOwnProperty.call(event.Artifact.Descriptor, 'MIME')
  ) {
    params.ContentType = event.Artifact.Descriptor.MIME;
  }

  // Assign all members of Parameters to params. Remove the properties required
  // for the Copy operation, so there is no collision
  if (
    Object.prototype.hasOwnProperty.call(event.Task.Destination, 'Parameters')
  ) {
    delete event.Task.Destination.Parameters.Bucket;
    delete event.Task.Destination.Parameters.Key;
    delete event.Task.Destination.Parameters.Body;

    Object.assign(params, event.Task.Destination.Parameters);
  }

  // Upload the resulting file to the destination in S3
  const uploadStart = process.hrtime();
  await s3writer.upload(params).promise();

  const uploadEnd = process.hrtime(uploadStart);
  console.log(
    JSON.stringify({
      msg: 'Finished S3 upload',
      duration: `${uploadEnd[0]} s ${uploadEnd[1] / 1000000} ms`,
    }),
  );
}

exports.handler = async (event) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  const s3 = new AWS.S3({ apiVersion: '2006-03-01' });
  const sts = new AWS.STS({ apiVersion: '2011-06-15' });

  // Fetch the source file artifact from S3
  console.log(
    JSON.stringify({
      msg: 'Fetching artifact from S3',
      s3: `${event.Artifact.BucketName}/${event.Artifact.ObjectKey}`,
    }),
  );

  const s3start = process.hrtime();

  const s3Object = await s3
    .getObject({
      Bucket: event.Artifact.BucketName,
      Key: event.Artifact.ObjectKey,
    })
    .promise();

  const s3end = process.hrtime(s3start);
  console.log(
    JSON.stringify({
      msg: 'Fetched artifact from S3',
      duration: `${s3end[0]} s ${s3end[1] / 1000000} ms`,
    }),
  );

  // create the wav object
  const wav = new wavefile.WaveFile();

  if (s3Object.Body instanceof Uint8Array || Buffer.isBuffer(s3Object.Body)) {
    wav.fromMpeg(s3Object.Body);
  }

  // If there are chunks passed in, iterate through each
  const resultChunks = [];
  event.Task.Chunks.forEach((taskChunk) => {
    // Set data if this is a chunk supported by wavefile
    const chunkId = taskChunk.ChunkId;
    if (Object.prototype.hasOwnProperty.call(wav, chunkId)) {
      Object.keys(taskChunk).forEach((taskKey) => {
        const wavKey = camelize(taskKey);
        if (
          !['chunkSize'].includes(wavKey) &&
          Object.prototype.hasOwnProperty.call(wav[chunkId], wavKey)
        ) {
          wav[chunkId][wavKey] = taskChunk[taskKey];
        }
      });
      resultChunks.push(wav[chunkId]);
    }
  });

  console.log(
    JSON.stringify({
      msg: 'Wavefile chunks set',
      chunks: resultChunks,
    }),
  );

  // save to s3 destination
  if (event.Task.Destination.Mode === 'AWS/S3') {
    await s3Upload(s3, sts, event, Buffer.from(wav.toBuffer()));
  }

  const now = new Date();

  return {
    Task: 'WavWrap',
    Mode: event.Task.Destination.Mode,
    BucketName: event.Task.Destination.BucketName,
    ObjectKey: event.Task.Destination.ObjectKey,
    Time: now.toISOString(),
    Timestamp: +now / 1000,
    WavefileChunks: resultChunks,
  };
};

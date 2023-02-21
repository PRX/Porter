const fs = require('fs');
const aws = require('aws-sdk');

const s3 = new aws.S3({ apiVersion: '2006-03-01' });
const sts = new aws.STS({ apiVersion: '2011-06-15' });

module.exports = {
  /**
   * Downloads the given S3 object to a local file path
   * @param {string} bucketName
   * @param {string} objectKey
   * @param {string} filePath
   */
  s3GetObject: function s3GetObject(bucketName, objectKey, filePath) {
    return new Promise((resolve, reject) => {
      const file = fs.createWriteStream(filePath);
      const stream = s3
        .getObject({
          Bucket: bucketName,
          Key: objectKey,
        })
        .createReadStream();

      stream.on('error', reject);
      file.on('error', reject);

      file.on('finish', () => {
        resolve(filePath);
      });

      stream.pipe(file);
    });
  },
  /**
   * Downloads the artifact from the Lambda input to a local file path
   * @param {object} event
   * @param {string} filePath
   */
  fetchArtifact: async function fetchArtifact(event, filePath) {
    console.log(
      JSON.stringify({
        msg: 'Fetching artifact from S3',
        s3: `${event.Artifact.BucketName}/${event.Artifact.ObjectKey}`,
        fs: filePath,
      }),
    );

    const s3start = process.hrtime();
    await this.s3GetObject(
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
  },
  s3Upload: async function s3Upload(event, waveformFileTmpPath) {
    const role = await sts
      .assumeRole({
        RoleArn: process.env.S3_DESTINATION_WRITER_ROLE,
        RoleSessionName: 'porter_waveform_task',
      })
      .promise();

    const s3writer = new aws.S3({
      apiVersion: '2006-03-01',
      accessKeyId: role.Credentials.AccessKeyId,
      secretAccessKey: role.Credentials.SecretAccessKey,
      sessionToken: role.Credentials.SessionToken,
    });

    const params = {
      Bucket: event.Task.Destination.BucketName,
      Key: event.Task.Destination.ObjectKey,
      Body: fs.createReadStream(waveformFileTmpPath),
    };

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
  },
};

// Because the result of a Fargate task is not sufficient for sending a proper
// callback, this function takes the entire task input and builds a better
// result that gets passed to the callback task.

const AWSXRay = require('aws-xray-sdk');

const AWS = AWSXRay.captureAWS(require('aws-sdk'));

const s3 = new AWS.S3({ apiVersion: '2006-03-01' });

class FtpError extends Error {
  constructor(...params) {
    super(...params);

    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, FtpError);
    }

    this.name = 'FtpError';
  }
}

exports.handler = async (event) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  const now = new Date();

  const ftpResultObjectKey = `${event.Execution.Id.split(':').pop()}-${
    event.TaskIteratorIndex
  }.FtpResult`;

  const file = await s3
    .getObject({
      Bucket: process.env.ARTIFACT_BUCKET_NAME,
      Key: ftpResultObjectKey,
    })
    .promise();

  const ftpResultJson = file.Body.toString();
  const ftpResult = JSON.parse(ftpResultJson);

  if (ftpResult.status !== 'COMPLETED') {
    throw new FtpError(ftpResult.message);
  }

  const result = {
    Task: event.Task.Type,
    URL: event.Task.URL,
    Time: now.toISOString(),
    Timestamp: +now / 1000,
  };

  console.log(JSON.stringify({ msg: 'Result', result }));

  return result;
};

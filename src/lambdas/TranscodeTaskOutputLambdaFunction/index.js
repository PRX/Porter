// Because the result of a Fargate task is not sufficient for sending a proper
// callback, this function takes the entire task input and builds a better
// result that gets passed to the callback task.

const AWSXRay = require('aws-xray-sdk');

const AWS = AWSXRay.captureAWS(require('aws-sdk'));

const s3 = new AWS.S3({ apiVersion: '2006-03-01' });

exports.handler = async (event) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  // Get ffprobe results
  const file = await s3
    .getObject({
      Bucket: process.env.ARTIFACT_BUCKET_NAME,
      Key: `${event.Execution.Id}/transcode/ffprobe-${event.TaskIteratorIndex}.json`,
    })
    .promise();
  const ffprobe = JSON.parse(file.Body.toString());

  const now = new Date();

  const result = {
    Task: event.Task.Type,
    BucketName: event.Task.Destination.BucketName,
    ObjectKey: event.Task.Destination.ObjectKey,
    Duration: +ffprobe.format.duration * 1000,
    Size: +ffprobe.format.size,
    Time: now.toISOString(),
    Timestamp: +now / 1000,
  };

  console.log(JSON.stringify({ msg: 'Result', result }));

  return result;
};

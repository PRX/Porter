// Invoked by a CloudWatch Events rule that is watching for
// TranscriptionJobStatus events. The details of the event include the
// transcription job name and status. The task token associated with the state
// machine execution that initiated the transcribe job gets pulled from S3,
// and SendTaskSuccess or SendTaskFailure is sent based on the results of the
// job.
//
// This will get triggered by *all* transcribe jobs, so the predefined prefix
// is used to filter out jobs originating elsewhere.

const AWSXRay = require('aws-xray-sdk');

const AWS = AWSXRay.captureAWS(require('aws-sdk'));

const s3 = new AWS.S3({ apiVersion: '2006-03-01' });
const stepFunctions = new AWS.StepFunctions({ apiVersion: '2016-11-23' });

exports.handler = async (event) => {
  console.log(JSON.stringify({ msg: 'Event', input: event }));

  const transcriptionJobName = event.detail.TranscriptionJobName;
  const transcriptionJobStatus = event.detail.TranscriptionJobStatus;

  // Ignore any events that don't have the prefix we're expecting for job names
  if (!transcriptionJobName.startsWith(process.env.TRANSCODE_JOB_NAME_PREFIX)) {
    return;
  }

  try {
    const file = await s3
      .getObject({
        Bucket: process.env.ARTIFACT_BUCKET_NAME,
        Key: `${transcriptionJobName}.TaskToken`,
      })
      .promise();

    const taskToken = file.Body.toString();

    if (transcriptionJobStatus === 'COMPLETED') {
      // The `output` parameter becomes the result value of the
      // ExecuteTranscribeTask state
      await stepFunctions
        .sendTaskSuccess({
          output: JSON.stringify({
            TranscriptionJobName: transcriptionJobName,
          }),
          taskToken,
        })
        .promise();
    } else {
      // TODO Add error/cause
      await stepFunctions
        .sendTaskFailure({
          taskToken,
        })
        .promise();
    }
  } catch (error) {
    // TODO
  }
};

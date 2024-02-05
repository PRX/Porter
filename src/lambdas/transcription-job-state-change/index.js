// Invoked by a CloudWatch Events rule that is watching for
// TranscriptionJobStatus events. The details of the event include the
// transcription job name and status. The task token associated with the state
// machine execution that initiated the transcribe job gets pulled from S3,
// and SendTaskSuccess or SendTaskFailure is sent based on the results of the
// job.
//
// This will get triggered by *all* transcribe jobs, so the predefined prefix
// is used to filter out jobs originating elsewhere.

import { S3Client, GetObjectCommand } from "@aws-sdk/client-s3";
import {
  SFNClient,
  SendTaskFailureCommand,
  SendTaskSuccessCommand,
} from "@aws-sdk/client-sfn";

const s3 = new S3Client({
  apiVersion: "2006-03-01",
  followRegionRedirects: true,
});
const sfn = new SFNClient({ apiVersion: "2016-11-23" });

export const handler = async (event) => {
  console.log(JSON.stringify({ msg: "Event", input: event }));

  const transcriptionJobName = event.detail.TranscriptionJobName;
  const transcriptionJobStatus = event.detail.TranscriptionJobStatus;

  // Ignore any events that don't have the prefix we're expecting for job names
  if (!transcriptionJobName.startsWith(process.env.TRANSCODE_JOB_NAME_PREFIX)) {
    return;
  }

  try {
    const file = await s3.send(
      new GetObjectCommand({
        Bucket: process.env.ARTIFACT_BUCKET_NAME,
        Key: `${transcriptionJobName}.TaskToken`,
      }),
    );

    const taskToken = await file.Body.transformToString();

    if (transcriptionJobStatus === "COMPLETED") {
      // The `output` parameter becomes the result value of the
      // ExecuteTranscribeTask state
      await sfn.send(
        new SendTaskSuccessCommand({
          output: JSON.stringify({
            TranscriptionJobName: transcriptionJobName,
          }),
          taskToken,
        }),
      );
    } else {
      // TODO Add error/cause
      await sfn.send(
        new SendTaskFailureCommand({
          taskToken,
        }),
      );
    }
  } catch (error) {
    // TODO
  }
};

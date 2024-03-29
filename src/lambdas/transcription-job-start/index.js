/* eslint-disable max-classes-per-file */
// Starts a transcription job in Amazon Transcribe for the artifact. This is
// called with the waitForTaskToken pattern, so once the job has finished
// something (not this function), will need to send a SendTaskSuccess message
// with the provided task token for the execution to proceed.
// A file is written to the artifact store in S3 containing the task token.
// The object key matches the transcribe job name, so that it can be deduced
// from events generated by the job.
//
// Job names are given a prefix that is unique to this deployment of Porter.
// This is necessary becasue the CloudWatch Events rule that watches for
// transcription jobs will fire for *all* jobs, so there needs to be a way to
// filter out jobs originating elsewhere.
//
// The results of this state are defined by the parameters passed to
// SendTaskSuccess, NOT this function.
//
// https://docs.aws.amazon.com/transcribe/latest/dg/API_StartTranscriptionJob.html

import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import {
  TranscribeClient,
  ListVocabularyFiltersCommand,
  CreateVocabularyFilterCommand,
  StartTranscriptionJobCommand,
} from "@aws-sdk/client-transcribe";

const s3 = new S3Client({
  apiVersion: "2006-03-01",
  followRegionRedirects: true,
});
const transcribe = new TranscribeClient({ apiVersion: "2017-10-26" });

class InvalidTranscribeTaskInputError extends Error {
  constructor(...params) {
    super(...params);
    this.name = "InvalidTranscribeTaskInputError";
  }
}

class UnknownDestinationModeError extends Error {
  constructor(...params) {
    super(...params);
    this.name = "UnknownDestinationModeError";
  }
}

export const handler = async (event) => {
  console.log(JSON.stringify({ msg: "State input", input: event }));

  let mediaFormat = event.Artifact.Descriptor.Extension;

  // Remap some common types to the equivalent required value that the
  // Transcribe API expects
  if (mediaFormat === "m4a") {
    mediaFormat = "mp4";
  } else if (mediaFormat === "3ga") {
    mediaFormat = "amr";
  } else if (mediaFormat === "oga" || mediaFormat === "opus") {
    mediaFormat = "ogg";
  }

  // Take your life in your own hands, force a format
  if (event.Task.MediaFormat) {
    mediaFormat = event.Task.MediaFormat;
  }

  // Check destination type before spending any time doing the work
  if (!["AWS/S3"].includes(event.Task.Destination.Mode)) {
    throw new UnknownDestinationModeError(
      `Unexpected destination mode: ${event.Task.Destination.Mode}`,
    );
  }

  // Only start the job if the artifact type (or passed in MediaFormat) is supported
  if (
    !["mp3", "mp4", "wav", "flac", "ogg", "amr", "webm"].includes(mediaFormat)
  ) {
    throw new InvalidTranscribeTaskInputError("Artifact format not supported");
  }

  // Only start the job if the subtitle formats provided are supported
  if (
    // If SubtitleFormats was included…
    event.Task.SubtitleFormats &&
    // Fail if it's not an array
    (!Array.isArray(event.Task.SubtitleFormats) ||
      // Fail if it's empty
      !event.Task.SubtitleFormats.length ||
      // Fail if it includes unsupported formats
      event.Task.SubtitleFormats.filter((f) => !["srt", "vtt"].includes(f))
        .length)
  ) {
    throw new InvalidTranscribeTaskInputError("Subtitle format not supported");
  }

  // Should be unique, even if an execution includes multiple transcribe jobs
  const prefix = process.env.TRANSCODE_JOB_NAME_PREFIX;
  const transcriptionJobName = `${prefix}${event.Execution.Id.split(
    ":",
  ).pop()}-${event.TaskIteratorIndex}`;

  // Write the task token provided by the state machine context to S3
  await s3.send(
    new PutObjectCommand({
      Bucket: event.Artifact.BucketName,
      Key: `${transcriptionJobName}.TaskToken`,
      Body: event.TaskToken,
    }),
  );

  // There seems to be some undocumented default filtering that Transcribe
  // does. Using a (mostly) empty vocab filter appears to disable that
  // filtering. This ensures that such a filter exists.
  // TODO This may not work with all LanguageCodes
  const filters = await transcribe.send(new ListVocabularyFiltersCommand({}));
  const filterName = `${process.env.AWS_LAMBDA_FUNCTION_NAME}-${event.Task.LanguageCode}`;
  if (
    !filters.VocabularyFilters.map((f) => f.VocabularyFilterName).includes(
      filterName,
    )
  ) {
    await transcribe.send(
      new CreateVocabularyFilterCommand({
        VocabularyFilterName: filterName,
        LanguageCode: event.Task.LanguageCode,
        // This is meant to be a nonsense word
        Words: ["abcdefghijklmnopqrstuvwxyz"],
      }),
    );
  }

  await transcribe.send(
    new StartTranscriptionJobCommand({
      Media: {
        // https://docs.aws.amazon.com/transcribe/latest/dg/API_Media.html
        // Expects s3://<bucket-name>/<keyprefix>/<objectkey>
        MediaFileUri: `s3://${event.Artifact.BucketName}/${event.Artifact.ObjectKey}`,
      },
      TranscriptionJobName: transcriptionJobName,
      LanguageCode: event.Task.LanguageCode,
      // Valid Values: mp3 | mp4 | wav | flac | ogg | amr | webm
      MediaFormat: mediaFormat,
      OutputBucketName: event.Artifact.BucketName,
      ...(event.Task?.SubtitleFormats?.length && {
        Subtitles: {
          Formats: event.Task.SubtitleFormats,
        },
      }),
      Settings: {
        VocabularyFilterName: filterName,
        VocabularyFilterMethod: "tag",
      },
      Tags: [
        {
          Key: "prx:ops:environment",
          Value: process.env.ENVIRONMENT_TYPE,
        },
        {
          Key: "prx:dev:application",
          Value: "Porter",
        },
      ],
    }),
  );
};

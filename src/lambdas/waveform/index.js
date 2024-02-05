/* eslint-disable max-classes-per-file */

import { join as pathJoin } from "node:path";
import { tmpdir } from "node:os";
import { unlinkSync } from "node:fs";
import { writeArtifact } from "porter-util";
import { s3Upload } from "./s3-util.js";
import { v1 as awfV1 } from "./generators/audiowaveform.js";

class UnknownDestinationModeError extends Error {
  constructor(...params) {
    super(...params);
    this.name = "UnknownDestinationModeError";
  }
}

class UnknownGeneratorError extends Error {
  constructor(...params) {
    super(...params);
    this.name = "UnknownGeneratorError";
  }
}

export const handler = async (event, context) => {
  console.log(JSON.stringify({ msg: "State input", input: event }));

  // Check destination type before spending any time doing the work
  if (!["AWS/S3"].includes(event.Task.Destination.Mode)) {
    throw new UnknownDestinationModeError(
      `Unexpected destination mode: ${event.Task.Destination.Mode}`,
    );
  }

  // Copy the source file artifact (the audio file) into the Lambda
  // environment's temporary storage
  const artifactTmpPath = await writeArtifact(event, context);

  // Define a path for the resulting waveform audio data file
  const waveformFileTmpPath = pathJoin(
    tmpdir(),
    `${context.awsRequestId}.${event.Artifact.Descriptor.Extension}.waveform`,
  );

  // Run the selected generator. Each of these is reponsible for producing a
  // file at the expected path.
  if (event.Task.Generator === "BBC/audiowaveform/v1.x") {
    await awfV1(event, artifactTmpPath, waveformFileTmpPath);
  } else {
    throw new UnknownGeneratorError(
      `Unexpected generator: ${event.Task.Generator}`,
    );
  }

  // Send the waveform data file to the destination
  if (event.Task.Destination.Mode === "AWS/S3") {
    await s3Upload(event, waveformFileTmpPath);
  }

  // Cleanup
  unlinkSync(artifactTmpPath);
  unlinkSync(waveformFileTmpPath);

  const now = new Date();

  return {
    Task: "Waveform",
    Mode: event.Task.Destination.Mode,
    BucketName: event.Task.Destination.BucketName,
    ObjectKey: event.Task.Destination.ObjectKey,
    Time: now.toISOString(),
    Timestamp: +now / 1000,
  };
};

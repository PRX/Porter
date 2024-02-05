import toAwsS3 from "./destination/aws-s3.js";
import toGcpStorage from "./destination/gcp-storage.js";

class UnknownCopyTaskModeError extends Error {
  constructor(...params) {
    super(...params);
    this.name = "UnknownCopyTaskModeError";
  }
}

export const handler = async (event) => {
  console.log(JSON.stringify({ msg: "State input", input: event }));

  switch (event.Task.Mode) {
    case "AWS/S3":
      await toAwsS3(event);
      break;
    case "GCP/Storage":
      await toGcpStorage(event);
      break;
    default:
      throw new UnknownCopyTaskModeError("Unexpected copy mode");
  }

  const now = new Date();

  return {
    Task: "Copy",
    Mode: event.Task.Mode,
    BucketName: event.Task.BucketName,
    ObjectKey: event.Task.ObjectKey,
    Time: now.toISOString(),
    Timestamp: +now / 1000,
  };
};

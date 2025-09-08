import { createReadStream } from "node:fs";
import { S3Client } from "@aws-sdk/client-s3";
import { AssumeRoleCommand, STSClient } from "@aws-sdk/client-sts";
import { Upload } from "@aws-sdk/lib-storage";

const sts = new STSClient({ apiVersion: "2011-06-15" });

export async function s3Upload(event, waveformFileTmpPath) {
  const role = await sts.send(
    new AssumeRoleCommand({
      RoleArn: process.env.S3_DESTINATION_WRITER_ROLE,
      RoleSessionName: "porter_waveform_task",
    }),
  );

  const s3writer = new S3Client({
    apiVersion: "2006-03-01",
    credentials: {
      accessKeyId: role.Credentials.AccessKeyId,
      secretAccessKey: role.Credentials.SecretAccessKey,
      sessionToken: role.Credentials.SessionToken,
    },
    followRegionRedirects: true,
  });

  const params = {
    Bucket: event.Task.Destination.BucketName,
    Key: event.Task.Destination.ObjectKey,
    Body: createReadStream(waveformFileTmpPath),
  };

  // Assign all members of Parameters to params. Remove the properties required
  // for the Copy operation, so there is no collision
  if (Object.hasOwn(event.Task.Destination, "Parameters")) {
    delete event.Task.Destination.Parameters.Bucket;
    delete event.Task.Destination.Parameters.Key;
    delete event.Task.Destination.Parameters.Body;

    Object.assign(params, event.Task.Destination.Parameters);
  }

  // Upload the resulting file to the destination in S3
  const uploadStart = process.hrtime();
  const upload = new Upload({ client: s3writer, params });
  await upload.done();
  const uploadEnd = process.hrtime(uploadStart);
  console.log(
    JSON.stringify({
      msg: "Finished S3 upload",
      duration: `${uploadEnd[0]} s ${uploadEnd[1] / 1000000} ms`,
    }),
  );
}

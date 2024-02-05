import { S3Client } from "@aws-sdk/client-s3";
import { STSClient, AssumeRoleCommand } from "@aws-sdk/client-sts";
import { Upload } from "@aws-sdk/lib-storage";
import { unlinkSync } from "node:fs";
import sharp from "sharp";
import { writeArtifact } from "porter-util";

const sts = new STSClient({ apiVersion: "2011-06-15" });

async function s3Upload(event, sharpInstance) {
  const role = await sts.send(
    new AssumeRoleCommand({
      RoleArn: process.env.S3_DESTINATION_WRITER_ROLE,
      RoleSessionName: "porter_image_task",
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
    Body: sharpInstance,
  };

  // When the optional `ContentType` property is set to `REPLACE`, if a MIME is
  // included with the artifact, that should be used as the new images's
  // content type
  if (
    Object.hasOwn(event.Task.Destination, "ContentType") &&
    event.Task.Destination.ContentType === "REPLACE" &&
    Object.hasOwn(event.Artifact, "Descriptor") &&
    Object.hasOwn(event.Artifact.Descriptor, "MIME")
  ) {
    params.ContentType = event.Artifact.Descriptor.MIME;
  }

  // Assign all members of Parameters to params. Remove the properties required
  // for the Copy operation, so there is no collision
  if (Object.hasOwn(event.Task.Destination, "Parameters")) {
    delete event.Task.Destination.Parameters.Bucket;
    delete event.Task.Destination.Parameters.Key;
    delete event.Task.Destination.Parameters.Body;

    Object.assign(params, event.Task.Destination.Parameters);
  }

  // Upload the resulting file to the destination in S3
  const upload = new Upload({ client: s3writer, params });
  await upload.done();
}

function sharpTransformer(inputFilePath, event) {
  let transformer = sharp(inputFilePath);

  if (Object.hasOwn(event.Task, "Resize")) {
    transformer = transformer.resize({
      width: event.Task.Resize.Width,
      height: event.Task.Resize.Height,
      position: event.Task.Resize.Position || "centre",
      fit: event.Task.Resize.Fit || "cover",
    });
  }

  if (Object.hasOwn(event.Task, "Format")) {
    transformer = transformer.toFormat(event.Task.Format);
  }

  if (
    Object.hasOwn(event.Task, "Metadata") &&
    event.Task.Metadata === "PRESERVE"
  ) {
    transformer = transformer.withMetadata();
  }

  return transformer;
}

export const handler = async (event, context) => {
  console.log(JSON.stringify({ msg: "State input", input: event }));

  // TODO If Sharp supports input streams some day, we can skip saving this
  // to a file
  const artifactTmpPath = await writeArtifact(event, context);

  const transformer = sharpTransformer(artifactTmpPath, event);

  if (event.Task.Destination.Mode === "AWS/S3") {
    await s3Upload(event, transformer);
  }

  unlinkSync(artifactTmpPath);

  const now = new Date();

  return {
    Task: "Image",
    Mode: event.Task.Destination.Mode,
    BucketName: event.Task.Destination.BucketName,
    ObjectKey: event.Task.Destination.ObjectKey,
    Time: now.toISOString(),
    Timestamp: +now / 1000,
  };
};

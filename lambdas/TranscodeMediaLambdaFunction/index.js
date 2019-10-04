
          const childProcess = require('child_process');
          const path = require('path');
          const os = require('os');
          const fs = require('fs');
          const awsxray = require('aws-xray-sdk');
          const aws = awsxray.captureAWS(require('aws-sdk'));

          const s3 = new aws.S3();

          function spawn(command, argsarray, envOptions) {
            return new Promise((resolve, reject) => {
              console.log('executing', command, argsarray.join(' '));

              const childProc = childProcess.spawn(command, argsarray, envOptions || { env: process.env, cwd: process.cwd() });
              const resultBuffers = [];

              childProc.stdout.on('data', buffer => resultBuffers.push(buffer));
              childProc.stderr.on('data', buffer => console.error(buffer.toString()));

              childProc.on('exit', (code, signal) => {
                console.log(`${command} completed with ${code}:${signal}`);

                if (code || signal) {
                  reject(`${command} failed with ${code || signal}`);
                } else {
                  resolve(Buffer.concat(resultBuffers).toString().trim());
                }
              });
            });
          }

          function s3GetObject(bucket, fileKey, filePath) {
            return new Promise(function (resolve, reject) {
              const file = fs.createWriteStream(filePath);
              const stream = s3.getObject({
                      Bucket: bucket,
                      Key: fileKey
                  }).createReadStream();

              stream.on('error', reject);
              file.on('error', reject);

              file.on('finish', function () {
                  console.log('downloaded', bucket, fileKey);
                  resolve(filePath);
              });

              stream.pipe(file);
            });
          }

          // Ex. input:  { "Artifact": { "BucketName": "SourceBucket", "ObjectKey": "Abc.wav" }, "Encoding": { "Format": "flac" } }
          // Ex. output: { "Task",: "Transcode", "Format": "flac", "BucketName": "ResultBucket", "ObjectKey": "Xyz.flac" }
          exports.handler = async (event, context) => {
              const artifactFileTmpPath = path.join(os.tmpdir(), context.awsRequestId);

              await s3GetObject(event.Artifact.BucketName, event.Artifact.ObjectKey, artifactFileTmpPath);
              console.log(`Got ${event.Artifact.BucketName}/${event.Artifact.ObjectKey} to ${artifactFileTmpPath}`);

              const transcodedMediaFilePath = `${artifactFileTmpPath}-transcoded.${event.Encoding.Format}`;
              console.log(`Transcoding as [${event.Encoding.Format}] to ${transcodedMediaFilePath}`);

              await spawn(
                  '/opt/bin/ffmpeg',
                  ['-loglevel', 'error', '-i', artifactFileTmpPath, transcodedMediaFilePath],
                  { env: process.env, cwd: os.tmpdir() }
              );
              console.log('finished transcode');

              if (event.Encoding.Destination.Mode === 'S3') {
                  // Upload the transcoded file to the destination specified in the job
                  const s3OutputBucketName = event.Encoding.Destination.BucketName;
                  const s3OutputObjectKey = event.Encoding.Destination.ObjectKey;

                  await s3.upload({
                      Bucket: s3OutputBucketName,
                      Key: s3OutputObjectKey,
                      Body: fs.createReadStream(transcodedMediaFilePath),
                  }).promise();
                  console.log(`Uploaded to ${s3OutputBucketName}/${s3OutputObjectKey}`);
              }

              fs.unlinkSync(artifactFileTmpPath);
              fs.unlinkSync(transcodedMediaFilePath);

              return {
                  'Task': 'Transcode',
                  'BucketName': event.Encoding.Destination.BucketName,
                  'ObjectKey': event.Encoding.Destination.ObjectKey
              };
          };

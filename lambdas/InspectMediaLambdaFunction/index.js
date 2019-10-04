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

function audioInspection(ffprobe, mpck) {
  const stream = ffprobe.streams.find(s => s.codec_type === 'audio');

  const inspection = {};

  if (stream) {
    Object.assign(inspection, {
      duration:  Math.round(stream.duration * 1000),
      format:    stream.codec_name,
      bitrate:   stream.bit_rate,
      frequency: stream.sample_rate,
      channels:  stream.channels,
      layout:    stream.channel_layout
    });
  }

  if (stream.codec_name === 'mp3') {
    Object.assign(inspection, {
      // TODO This is bad
      layer: (mpck.match(/layer (.+)/) ? mpck.match(/layer (.+)/)[1] : null),
      samples: (mpck.match(/samples (.+)/) ? mpck.match(/samples (.+)/)[1] : null),
      frames: (mpck.match(/frames (.+)/) ? mpck.match(/frames (.+)/)[1] : null)
    });
  }

  return inspection;
}

function videoInspection(ffprobe, mpck) {
  const stream = ffprobe.streams.find(s => s.codec_type === 'video' && s.duration > 0 && s.bit_rate > 0);

  if (stream) {
    return {
      duration:  Math.round(stream.duration * 1000),
      format:    stream.codec_name,
      bitrate:   stream.bit_rate,
      width:     stream.width,
      height:    stream.height,
      aspect:    stream.display_aspect_ratio,
      framerate: stream.r_frame_rate
    };
  }
}

// Ex. input:  { "Artifact": { "BucketName": "SourceBucket", "ObjectKey": "Abc.wav" }, "Encoding": { "Format": "flac" } }
// Ex. output: { "Task",: "Transcode", "Format": "flac", "BucketName": "ResultBucket", "ObjectKey": "Xyz.flac" }
exports.handler = async (event, context) => {
  const artifactFileTmpPath = path.join(os.tmpdir(), context.awsRequestId);

  console.log(`Getting ${event.Artifact.BucketName}/${event.Artifact.ObjectKey} to ${artifactFileTmpPath}`);
  await s3GetObject(event.Artifact.BucketName, event.Artifact.ObjectKey, artifactFileTmpPath);
  console.log(`Got ${event.Artifact.BucketName}/${event.Artifact.ObjectKey} to ${artifactFileTmpPath}`);

  const json = await spawn('/opt/bin/ffprobe',
                      ['-v', 'error', '-show_streams', '-show_format', '-i', artifactFileTmpPath, '-print_format', 'json'],
                      { env: process.env, cwd: os.tmpdir() });
  const ffprobe = JSON.parse(json);

  const mpck = await spawn('/opt/bin/mpck',
                      ['-v', artifactFileTmpPath],
                      { env: process.env, cwd: os.tmpdir() });

  fs.unlinkSync(artifactFileTmpPath);

  const inspection = { size: ffprobe.format.size };

  Object.assign(inspection, { audio: audioInspection(ffprobe, mpck) });
  Object.assign(inspection, { video: videoInspection(ffprobe, mpck) });

  return { Task: 'Inspect', Inspection: inspection };
};

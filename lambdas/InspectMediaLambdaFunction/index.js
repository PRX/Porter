const childProcess = require('child_process');
const path = require('path');
const os = require('os');
const fs = require('fs');
const awsxray = require('aws-xray-sdk');
const aws = awsxray.captureAWS(require('aws-sdk'));

const s3 = new aws.S3();

function spawn(command, argsarray, envOptions) {
  return new Promise((resolve, reject) => {
    console.log(JSON.stringify({
      msg: 'Spawning child process',
      command: command,
      arguments: argsarray
    }));

    const childProc = childProcess.spawn(command, argsarray, envOptions || { env: process.env, cwd: process.cwd() });
    const resultBuffers = [];

    childProc.stdout.on('data', buffer => resultBuffers.push(buffer));
    childProc.stderr.on('data', buffer => console.error(buffer.toString()));

    childProc.on('exit', (code, signal) => {
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
      Duration:  Math.round(stream.duration * 1000),
      Format:    stream.codec_name,
      Bitrate:   stream.bit_rate,
      Frequency: stream.sample_rate,
      Channels:  stream.channels,
      Layout:    stream.channel_layout
    });
  }

  if (stream.codec_name === 'mp3') {
    Object.assign(inspection, {
      // TODO This is bad
      Layer: (mpck.match(/layer (.+)/) ? mpck.match(/layer (.+)/)[1].trim() : null),
      Samples: (mpck.match(/samples (.+)/) ? mpck.match(/samples (.+)/)[1].trim() : null),
      Frames: (mpck.match(/frames (.+)/) ? mpck.match(/frames (.+)/)[1].trim() : null)
    });
  }

  return inspection;
}

function videoInspection(ffprobe, mpck) {
  const stream = ffprobe.streams.find(s => s.codec_type === 'video' && s.duration > 0 && s.bit_rate > 0);

  if (stream) {
    return {
      Duration:  Math.round(stream.duration * 1000),
      Format:    stream.codec_name,
      Bitrate:   stream.bit_rate,
      Width:     stream.width,
      Height:    stream.height,
      Aspect:    stream.display_aspect_ratio,
      Framerate: stream.r_frame_rate
    };
  }
}

// Ex. input:  { "Artifact": { "BucketName": "SourceBucket", "ObjectKey": "Abc.wav" }, "Encoding": { "Format": "flac" } }
// Ex. output: { "Task",: "Transcode", "Format": "flac", "BucketName": "ResultBucket", "ObjectKey": "Xyz.flac" }
exports.handler = async (event, context) => {
  const artifactFileTmpPath = path.join(os.tmpdir(), context.awsRequestId);

  console.log(JSON.stringify({ msg: 'State input', input: event }));

  console.log(JSON.stringify({
    msg: 'Fetching artifact from S3',
    s3: `${event.Artifact.BucketName}/${event.Artifact.ObjectKey}`,
    fs: artifactFileTmpPath
  }));

  const _s3start = process.hrtime();
  await s3GetObject(event.Artifact.BucketName, event.Artifact.ObjectKey, artifactFileTmpPath);

  const _s3end = process.hrtime(_s3start);
  console.log(JSON.stringify({
    msg: 'Fetching artifact from S3',
    duration: `${_s3end[0]} s ${_s3end[1] / 1000000} ms`
  }));

  const _ffstart = process.hrtime();
  const json = await spawn('/opt/bin/ffprobe',
                      ['-v', 'error', '-show_streams', '-show_format', '-i', artifactFileTmpPath, '-print_format', 'json'],
                      { env: process.env, cwd: os.tmpdir() });
  const ffprobe = JSON.parse(json);

  const _ffend = process.hrtime(_ffstart);
  console.log(JSON.stringify({
    msg: 'Finished ffprobe',
    duration: `${_ffend[0]} s ${_ffend[1] / 1000000} ms`,
    data: ffprobe
  }));

  const _mpstart = process.hrtime();
  const mpck = await spawn('/opt/bin/mpck',
                      ['-v', artifactFileTmpPath],
                      { env: process.env, cwd: os.tmpdir() });

  const _mpend = process.hrtime(_mpstart);
  console.log(JSON.stringify({
    msg: 'Finished mpck',
    duration: `${_mpend[0]} s ${_mpend[1] / 1000000} ms`,
    data: mpck
  }));


  fs.unlinkSync(artifactFileTmpPath);

  const inspection = { Size: ffprobe.format.size };

  Object.assign(inspection, { Audio: audioInspection(ffprobe, mpck) });
  Object.assign(inspection, { Video: videoInspection(ffprobe, mpck) });
  Object.assign(inspection, event.Artifact.Descriptor);

  return { Task: 'Inspect', Inspection: inspection };
};

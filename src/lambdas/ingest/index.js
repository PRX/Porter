/* eslint-disable max-classes-per-file */
// This function is invoked at the start of a state machine execution, and
// ingests the source file declared in the job to a short-term S3 bucket.
// Subsequent states in the step function access the file from that location.
// Source files can be ingested from either S3 or HTTP origins.
//
// The input for this state is the original job object that was sent as input
// to the state machine execution, eg:
// { "Job": { "Id": "xyz", "Source": { "URI": "s3://myBucket/myObject" }, … } }
//
// The input path for this Lambda function is explicitly defined parameters, eg
// { "Job": { "Source": { "URI": "s3://myBucket/myObject" } }, "Execution": { "Id": "x85a61ed-ff52-5291-debd-616797212639" } }
//
// The function returns an object like
// { "BucketName": "abc", "ObjectKey": "xyz" }
//
// The result path is $.Artifact, so the output of the state looks like
// { "Job": { … }, "Artifact": { "BucketName": "abc", "ObjectKey": "xyz" } }

const path = require('path');
const os = require('os');
const fs = require('fs');

const http = require('http');
const https = require('https');
const AWS = require('aws-sdk');

const s3 = new AWS.S3({ apiVersion: '2006-03-01' });

class UnknownSourceModeError extends Error {
  constructor(...params) {
    super(...params);
    this.name = 'UnknownSourceModeError';
  }
}

class InvalidDataUriError extends Error {
  constructor(...params) {
    super(...params);
    this.name = 'InvalidDataUriError';
  }
}

// Requests a file over HTTP and writes it to disk
function httpGet(uri, file, redirectCount) {
  return new Promise((resolve, reject) => {
    const client = uri.toLowerCase().startsWith('https') ? https : http;

    const q = new URL(uri);

    const options = {
      host: q.host,
      port: q.port,
      path: `${q.pathname || ''}${q.search || ''}`,
      headers: {
        'User-Agent': 'PRX-Porterbot/1.0 (+https://github.com/PRX/Porter)',
      },
    };

    client
      .get(options, async (res) => {
        if (res.statusCode === 301 || res.statusCode === 302) {
          try {
            if (redirectCount > +process.env.MAX_HTTP_REDIRECTS) {
              reject(new Error('Too many redirects'));
            }

            console.log(
              JSON.stringify({
                msg: `Following HTTP redirect`,
                location: res.headers.location,
                count: redirectCount,
              }),
            );

            const count = redirectCount ? redirectCount + 1 : 1;
            await httpGet(res.headers.location, file, count);
            resolve();
          } catch (error) {
            reject(error);
          }
        } else if (res.statusCode >= 200 && res.statusCode < 300) {
          file.on('finish', () => file.close(() => resolve()));
          file.on('error', (error) => {
            fs.unlinkSync(file);
            reject(error);
          });

          res.pipe(file);
        } else {
          reject(new Error(`HTTP request failed with code ${res.statusCode}`));
        }
      })
      .on('error', (error) => reject(error));
  });
}

function filenameFromSource(source) {
  if (source.Mode === 'HTTP') {
    const urlObj = new URL(source.URL);
    return (
      decodeURIComponent(urlObj.pathname.split('/').pop()) || urlObj.hostname
    );
  }

  if (source.Mode === 'AWS/S3') {
    return source.ObjectKey.split('/').pop();
  }

  return false;
}
exports.filenameFromSource = filenameFromSource;

exports.handler = async (event, context) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  const sourceFilename = filenameFromSource(event.Job.Source);

  const artifact = {
    BucketName: process.env.ARTIFACT_BUCKET_NAME,
    ObjectKey: `${event.Execution.Id}/${context.awsRequestId}/${sourceFilename}`,
  };

  if (event.Job.Source.Mode === 'HTTP') {
    // Downloads the HTTP resource to a file on disk in the Lambda's tmp
    // directory, and then uploads that file to the S3 artifact bucket.
    const localFilePath = path.join(os.tmpdir(), sourceFilename);

    const localFile = fs.createWriteStream(localFilePath);

    const httpstart = process.hrtime();
    await httpGet(event.Job.Source.URL, localFile);

    const httpend = process.hrtime(httpstart);
    console.log(
      JSON.stringify({
        msg: 'Finished HTTP request',
        duration: `${httpend[0]} s ${httpend[1] / 1000000} ms`,
      }),
    );

    const s3start = process.hrtime();
    await s3
      .upload({
        Bucket: artifact.BucketName,
        Key: artifact.ObjectKey,
        Body: fs.createReadStream(localFilePath),
      })
      .promise();

    const s3end = process.hrtime(s3start);
    console.log(
      JSON.stringify({
        msg: 'Finished S3 upload',
        duration: `${s3end[0]} s ${s3end[1] / 1000000} ms`,
      }),
    );

    fs.unlinkSync(localFilePath);
  } else if (event.Job.Source.Mode === 'AWS/S3') {
    // Copies an existing S3 object to the S3 artifact bucket.
    // https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#copyObject-property
    // https://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectCOPY.html
    // CopySource expects: "/sourcebucket/path/to/object.extension"
    // CopySource expects "/sourcebucket/path/to/object.extension" to be URI-encoded
    const start = process.hrtime();

    await s3
      .copyObject({
        CopySource: encodeURI(
          `/${event.Job.Source.BucketName}/${event.Job.Source.ObjectKey}`,
        ).replace(/\+/g, '%2B'),
        Bucket: artifact.BucketName,
        Key: artifact.ObjectKey,
      })
      .promise();

    const end = process.hrtime(start);

    console.log(
      JSON.stringify({
        msg: 'Finished S3 Copy',
        duration: `${end[0]} s ${end[1] / 1000000} ms`,
      }),
    );
  } else if (event.Job.Source.Mode === 'Data/URI') {
    // e.g., data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7
    const uri = event.Job.Source.URI;

    if (!/^data:[\w/+-]+;base64,/.test(uri)) {
      throw new InvalidDataUriError('Invalid Data URI');
    }

    const base64Data = uri.split(';base64,')[1];

    const s3start = process.hrtime();
    await s3
      .upload({
        Bucket: artifact.BucketName,
        Key: artifact.ObjectKey,
        Body: Buffer.from(base64Data, 'base64'),
      })
      .promise();

    const s3end = process.hrtime(s3start);
    console.log(
      JSON.stringify({
        msg: 'Finished S3 upload',
        duration: `${s3end[0]} s ${s3end[1] / 1000000} ms`,
      }),
    );
  } else {
    throw new UnknownSourceModeError('Unexpected source mode');
  }

  return artifact;
};

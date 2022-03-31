const path = require('path');
const os = require('os');
const fs = require('fs');
const http = require('http');
const https = require('https');
const AWS = require('aws-sdk');

const s3 = new AWS.S3({ apiVersion: '2006-03-01' });

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

/**
 * Requests a file over HTTP and writes it to disk
 * @param {object} event
 * @param {object} artifact
 * @param {string} sourceFilename
 */
module.exports = async function main(event, artifact, sourceFilename) {
  // Downloads the HTTP resource to a file on disk in the Lambda's tmp
  // directory, and then uploads that file to the S3 artifact bucket.
  const localFilePath = path.join(os.tmpdir(), sourceFilename);

  const localFile = fs.createWriteStream(localFilePath);

  await httpGet(event.Job.Source.URL, localFile);

  await s3
    .upload({
      Bucket: artifact.BucketName,
      Key: artifact.ObjectKey,
      Body: fs.createReadStream(localFilePath),
    })
    .promise();

  fs.unlinkSync(localFilePath);
};

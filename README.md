# Porter

tktktk

## Messaging I/O

Porter receives messages to start jobs, and sends messages while jobs are running, and when jobs complete or fail.

### Starting a Job

When you want to start a job, a message must be sent to Porter. This can be done either directly through the [AWS Step Functions API](https://docs.aws.amazon.com/step-functions/latest/apireference/Welcome.html), or by way of an SNS topic that is created along side the state machine when the CloudFormation stack is launched.

**API Example**

```
import boto3
stepfunctions = boto3.client('stepfunctions')
stepfunctions.start_execution(
    stateMachineArn='arn:aws:states:us-east-2:1234512345:stateMachine:StateMachine-u827adsf8',
    input='{"Job": { … }}'
)
```

**SNS Example**

```
import boto3
sns = boto3.client('sns')
sns.publish(
    TopicArn='arn:aws:sns:us-east-2:1234512345:SnsTopic-ABCDE1234',
    Message='{"Job": { … }}'
)
```

### Input Message Format

```
{
    "Job": {
        "Id": "1234567890asdfghjkl"
        "Source": {
            "Mode": "AWS/S3",
            "BucketName": "farski-sandbox-prx",
            "ObjectKey": "130224.mp2"
        },
        "Inspect": {
            "Perform": true
        },
        "Copy": {
            "Destinations": [
                {
                    "Mode": "AWS/S3",
                    "BucketName": "myBucket",
                    "ObjectKey": "audioFile-copy.wav"
                }
            ]
        },
        "Transcode": {
            "Encodings": [
                {
                    "Format": "flac",
                    "Destination": {
                        "Mode": "AWS/S3",
                        "BucketName": "myBucket",
                        "ObjectKey": "audioFile-copy.wav"
                    }
                }
            ]
        },
        "Callbacks": [
            {
                "Type": "AWS/SNS",
                "Topic": "arn:aws:sns:us-east-2:127213743756:my-callback-topic"
            }, {
                "Type": "AWS/SQS",
                "Queue": "https://sqs.us-east-2.amazonaws.com/1234512355/my-callback-queue"
            }, {
                "Type": "HTTP",
                "URL": "https://example.com/callbacks/jobs"
                "Method": "POST",
                "Content-Type": "application/json"
            }, {
                "Type": "HTTP",
                "URL": "https://example.com/callbacks/jobs",
                "Method": "PUT",
                "Content-Type": "application/x-www-form-urlencoded"
            }, {
                "Type": "HTTP",
                "URL": "https://example.com/callbacks/jobs",
                "Method": "GET",
                "Name": "payload"
            }
        ]
    }
}
```

Input messages are represented as JSON data.

The `Job.Id` is a user-defined value, and is distinct from any execution IDs created when the job runs. The `Job.Id` is sent in all callback messages. It is required.

`Source.Mode` is required and indicates the protocol used to fetch the source file. When the mode is set to `S3`, `Source.BucketName` and `Source.ObjectKey` are also required. When the mode is set to `HTTP`, `Source.URL` is also required, which can use either an `http://` or `https://` protocol.

`Inspect`, `Copy`, and `Transcode` are the various tasks that can be run during a job execution. Each task type will have its own format.

`Callbacks` is an array of endpoints to which callback messages about the job execution will be sent. Each endpoint object has a `Type` (supported types are `AWS/SNS`, `AWS/SQS`, and `HTTP`). Different modes will have additional required properties.

### Callback Messages

Callback messages are dispatched at various points throughout the execution of a job. Whenever callback messages are sent, messages are always sent to all callbacks defined in the job. Callbacks are optional, and any value in `Job.Callbacks` other than an array will be ignored. Empty arrays are okay.

Each callback includes `Time` and `Timestamp` values. These represent approximately the time at which that specific callback was sent. If multiple callbacks are provided for a job, they may (and likely will) have slightly different timestamps, even though they are sent in parallel. These time values are in addition to the ones included with individual task results, and should always be later (greater than) the task-specific values.

Callbacks are sent when a job has been received (after the input has been normalized). These callbacks will contain a `JobReceived` key.

```
{
    "Time": "2012-12-21T12:34:56Z",
    "Timestamp: 1356093296.123,
    "JobReceived": {
        "Job": {
            "Id": "1234567890asdfghjkl"
        },
        "Execution": {
            "Id": "arn:aws:states:us-east-1:561178107736:execution:StateMachine-cvPVX5enHWdj:221672a9-ada6-483f-a5a7-ccffd4eee8c5"
        }
    }
}
```

Callbacks are sent as individual tasks are completed. For example, if a job includes three `Copy` destinations, a callback will be sent after each copy task completes. (Tasks are processed in parallel, so callbacks may arrive in any order). Task callbacks can be identified by the `TaskResult` key. The JSON message for a `Copy` task callback looks like this:

```
{
    "Time": "2012-12-21T12:34:56Z",
    "Timestamp: 1356093296.123,
    "TaskResult": {
        "Job": {
            "Id": "1234567890asdfghjkl"
        },
        "Execution": {
            "Id": "arn:aws:states:us-east-1:561178107736:execution:StateMachine-cvPVX5enHWdj:221672a9-ada6-483f-a5a7-ccffd4eee8c5"
        },
        "Result": {
            "Task": "Copy"
            "Time": "2012-12-21T12:34:50Z",
            "Timestamp: 1356093290.123,
            (Additional task-specific results)
        }
    }
}
```

> Note: If an individual task fails, there is no task-level error callback that gets sent. A failure in any part of the state machine will cause the entire state machine to fail, and the error will be reported in the job error callback.

Callbacks are also sent when the job completes. Job callbacks can be identified by the `JobResult` key. The callback message includes information about all tasks that were completed. When the job was successful, the `JobResult` object will include a `Result` key.

```
{
    "Time": "2012-12-21T12:34:56Z",
    "Timestamp: 1356093296.123,
    "JobResult": {
        "Job": {
            "Id": "1234567890asdfghjkl"
        },
        "Execution": {
            "Id": "arn:aws:states:us-east-1:561178107736:execution:StateMachine-cvPVX5enHWdj:221672a9-ada6-483f-a5a7-ccffd4eee8c5"
        },
        "Result": [
            {
                "Task": "Copy"
                (Additional task-specific results)
            }, {
                "Task": "Copy"
                (Additional task-specific results)
            }, {
                "Task": "Transcode"
                (Additional task-specific results)
            }, {
                "Task": "Inspect"
                (Additional task-specific results)
            }
        ]
    }
}
```

If there's a failure during the job execution in any part of the state machine, the error will be caught and a single job failure callback message is sent. These messages will **not** include a `Result` key in `JobResult`, but will include an `Error` key.

```
{
    "Time": "2012-12-21T12:34:56Z",
    "Timestamp: 1356093296.123,
    "JobResult": {
        "Job": {
            "Id": "1234567890asdfghjkl"
        },
        "Execution": {
            "Id": "arn:aws:states:us-east-1:561178107736:execution:StateMachine-cvPVX5enHWdj:221672a9-ada6-483f-a5a7-ccffd4eee8c5"
        },
        "Error": {
            (Details about the error)
        }
    }
}
```

**Example:** If you have a job with three copy destinations, and two callbacks, you would expect to get a total of six `TaskResult` and two `JobResult` messages, across all of the endpoints.

## Tasks

### Copy

`Copy` tasks create copies of the job's source file at one or more `Destinations` defined on the task. Currently the only supported destination mode is `AWS/S3`. Copy tasks **do not** check if an object already exists in the given location. A copy task can include any number of destinations.

If `Job.Copy.Destinations` is not an array with at least one element, the state machine will act as though no copy tasks were included in the job.

The `Time` and `Timestamp` in the output represent approximately when the file finished being copied.

#### AWS/S3

 S3 copy operations are done by the [copyObject()](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#copyObject-property) method in the AWS Node SDK. Copying files larger than 5 GB is not supported by the AWS API.

The `BucketName` and `ObjectKey` properties are required.

The default behavior is to preserve all metadata except for the ACL, which is set to private. To set new metadata on the copy, use the optional `Parameters` property on the destination. `MetadataDirective` must be set to `REPLACE` for the operation to honor the new metadate. The contents of `Parameters` are passed directly to the [copyObject()](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#copyObject-property) method.

If you set the optional `ContentType` property to `REPLACE`, the content type of the newly created copy will be set to a [heuristically-determined](https://www.npmjs.com/package/file-type) value. This would replace the content type copied from the source object, if such a value existed. If the content type could not be determined heuristically, this property has no effect. Setting `ContentType` to `REPLACE` will also set `MetadataDirective` to `REPLACE`. If a `ContentType` value is explicitly defined in `Parameters` that value will take precedence.

Input:

```
{
    "Copy": {
        "Destinations": [
            {
                "Mode": "AWS/S3",
                "BucketName": "myBucket",
                "ObjectKey": "myObject.ext"
            }
        ]
    }
}
```

Input with additional parameters:

```
{
    "Copy": {
        "Destinations": [
            {
                "Mode": "AWS/S3",
                "BucketName": "myBucket",
                "ObjectKey": "myObject.ext",
                "ContentType": "REPLACE",
                "Parameters": {
                    "ACL": "public-read"
                    "ContentDisposition": "attachment"
                    "Metadata": {
                        "MyMetadataKey": "MyMetadataValue"
                    },
                    "MetadataDirective": "REPLACE"
                }
            }
        ]
    }
}
```

Output:

```
{
    "Task": "Copy",
    "BucketName": "myBucket",
    "ObjectKey": "myObject.ext",
    "Time": "2012-12-21T12:34:56Z",
    "Timestamp: 1356093296.123
}
```

### Image Transform

`Image` tasks perform image manipulations on the source file. These are intended for static image files (eg, jpeg, png, webp, gif, svg. Currently the only supported destination mode is `AWS/S3`.

Resize supports the following parameters: `Fit`, `Height`, `Position`, and `Width`. These follow the same rules as [sharp's](http://sharp.pixelplumbing.com/en/stable/api-resize/#parameters) parameters. The `Resize` property is optional; if excluded the task will not attempt to resize the image. All child properties of the `Resize` object are optional.

`Format` indicates the desired output format. Supported formats are: `jpeg`, `png`, `webp`, and `tiff`. The `Format` property is optional; if excluded the output format will be inferred from the file extension of the destination object.

By default all image metadata (EXIF, XMP, IPTC, etc) is stripped away during processing. If you set `Metadata` to `PRESERVE`, metadata from the input file will be included in the output file. This property is optional, and other values have no effect.

If `Job.Image.Transforms` is not an array with at least one element, the state machine will act as though no copy tasks were included in the job.

Input:

```
{
    "Image": {
        "Transforms": [
            {
                "Format": "png",
                "Metadata": "PRESERVE",
                "Resize": {
                    "Fit": "cover",
                    "Height": 300,
                    "Position": "centre"
                    "Width": 300
                },
                "Destination": {
                    "Mode": "AWS/S3",
                    "BucketName": "myBucket",
                    "ObjectKey": "myObject.png"
                }
            }
        ]
    }
}
```

Output:

```
{
    "Task": "Image",
    "BucketName": "myBucket",
    "ObjectKey": "myObject.ext",
    "Time": "2012-12-21T12:34:56Z",
    "Timestamp: 1356093296.123
}
```

### Transcode (WIP)

`Transcode` tasks encode and otherwise manipulate the source file. These are intended for audio and video source files. The desired transcoding are declared as `Encodings`, and each encoding includes the properties of the output file, and a single destination for the output file to be sent to. A transcode task can include any number of encodings. Currently the only supported destination mode is `AWS/S3`.

The `Format` is used to explicitly set the output format of the encoding operation; it is not implictly determined by the file extension. The available formats are indicted [in this list](https://johnvansickle.com/ffmpeg/release-readme.txt) with an `E`.

If `Job.Transcode.Encodings` is not an array with at least one element, the state machine will act as though no copy tasks were included in the job.

Input:

```
{
    "Transcode": {
        "Encodings": [
            {
                "Format": "flac",
                "Destination": {
                    "Mode": "AWS/S3",
                    "BucketName": "myBucket",
                    "ObjectKey": "myObject.flac"
                }
            }
        ]
    }
}
```

Output:

```
{
    "Task": "Transcode",
    "BucketName": "myBucket",
    "ObjectKey": "myObject.flac"
}
```

### Inspect (WIP)

`Inspect` tasks performs an analysis of the job's source file, and returns a set of metadata. The method of analysis and resulting data are determined by the type of the source file.

Input:

```
{
    "Inspect": {
        "Perform": true
    }
}
```

Output:

```
{
    "Task": "Inspect",
    "Inspection": {
        (The results of the analysis.)
    }
}
```

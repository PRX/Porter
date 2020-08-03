# Porter

Porter is a general-purpose file processing system. It is designed to work asynchronously – jobs are sent to Porter from other applications, and the results can be returned to the applications via callbacks. It supports a variety of tasks that can be run on the files included in each job. Some are generic tasks (such as copying a file to a new location), and some are specific to certain file types (such as resizing an image, or transcoding an audio file).

Porter is built on top of [AWS Step Functions](https://aws.amazon.com/step-functions/), as well a number of other AWS services. Each job that is sent to Porter for processing corresponds to a single state machine [execution](https://docs.aws.amazon.com/step-functions/latest/dg/concepts-state-machine-executions.html) of the Step Function. Each Porter job represents one (and only one) input file, which is considered the job's _source file_. Every task that the job definition includes is run against that original source file in parallel.

The system is design to be highly scalable, both in terms of the number of jobs that can be processed, as well as the number of tasks an individual job can include. Many of the states that the Step Function orchestrates are built on [AWS Lambda](https://aws.amazon.com/lambda/) and [AWS Fargate](https://aws.amazon.com/fargate/), which are serverless compute platforms and support that scalability. As such, there are no prioritization options or explicit queueing controls available. It can be assumed that jobs begin to execute as soon as they are received by Porter.

Porter utilizes the robust [error handling](https://docs.aws.amazon.com/step-functions/latest/dg/concepts-error-handling.html) and retry logic that Step Functions offer to ensure that tasks are resilient to transient service issues. In cases where a job execution is not able to complete all its tasks, Porter sends callbacks to indicate the failure, and the application must decide how to attempt to retry the work.

Job executions within Porter are not intended to be inspected directly or in real time by other applications. An application that's submitting jobs should be designed to track the state of its jobs based on the callback messages that it has or has not received. Callback messages are sent at various points during a job execution, which is explained in more detail [below](#callback-messages).

Many input and output methods are supported to allow flexibility with other applications. For example, source files can come from HTTP or S3 endpoints, and callback messages can be sent via HTTP, [SNS](https://aws.amazon.com/sns/), and [SQS](https://aws.amazon.com/sqs/). The list of supported source and destination methods will grow over time; see below for a more complete list of methods that each aspect of the job execution support.

### Table of Contents

- [Introduction](#porter)
- [Execution Model](#execution-model)
- [Messaging I/O](#messaging-io)
  - [Starting a Job](#starting-a-job)
  - [Input Message Format](#input-message-format)
  - [Callback Messages](#callback-messages)
- [Tasks](#tasks)
  - [Inspect](#inspect)
  - [Copy](#copy)
  - [Image Transform](#image-transform)
  - [Transcode](#transcode)
  - [Transcribe](#transcribe)
  - [WAV Wrap](#wav-)
- [Serialized Jobs](#serialized-jobs)
- [S3 Destination Permissions](#s3-destination-permissions)

## Execution Model

A Porter job represents a set of work (tasks) to be done for a source file. Each job has only a single source file, and that file is immutable in the context of the job execution. If a task does work to copy, transform, or otherwise manipulate the source file, the result of that operation will be a new file, leaving the source file unchanged. Individual tasks define the locations for those resulting files to be persisted.

Job tasks are isolated and independent from each other. They are run in parallel, and the output of one task cannot be used as the input for another task. The order in which tasks are started is not guaranteed. A job will run until all its tasks have either succeeded or failed. If a job includes multiple tasks and one task fails, that will not cause the rest of the execution to halt or fail.

In some cases, a job may encounter an issue before it can start any of its tasks, such as if the source file is unavailable.

Except in cases where Porter is unable to send callbacks, every Porter job will return a result, regardless of how successful it was. The result may indicate that the job was entirely successful, partially successful, or entirely unsuccessful. Applications consuming callbacks from Porter should be designed to handle that spectrum of results.

Individual task results, on the other hand, are binary: a task is either successful and returns the result of the task operation, or the task failed and it reports the failure.

## Messaging I/O

Porter receives messages to start jobs, and sends messages while jobs are running and when jobs are done.

### Starting a Job

When you want to start a job, a message must be sent to Porter. This can be done either directly through the [AWS Step Functions API](https://docs.aws.amazon.com/step-functions/latest/apireference/Welcome.html), or by way of an SNS topic that is created along side the state machine when the CloudFormation stack is launched.

**API Example**

```python
import boto3
stepfunctions = boto3.client('stepfunctions')
stepfunctions.start_execution(
    stateMachineArn='arn:aws:states:us-east-2:1234512345:stateMachine:StateMachine-u827adsf8',
    input='{"Job": { … }}'
)
```

**SNS Example**

```python
import boto3
sns = boto3.client('sns')
sns.publish(
    TopicArn='arn:aws:sns:us-east-2:1234512345:SnsTopic-ABCDE1234',
    Message='{"Job": { … }}'
)
```

### Input Message Format

Input messages are represented as JSON data. The root JSON object must include a `Job` key. All information needed to define the job will be enclosed in the `Job` object.

```json
{
  "Job": {
    "Id": "1234567890asdfghjkl",
    "Source": {
      "Mode": "AWS/S3",
      "BucketName": "myBucket",
      "ObjectKey": "myObject.jpg"
    },
    "Tasks": [
      {
        "Type": "Inspect"
      }
    ],
    "Callbacks": [
      {
        "Type": "AWS/SNS",
        "Topic": "arn:aws:sns:us-east-1:123456789012:my-callback-topic"
      }
    ]
  }
}
```

#### Job ID

The job ID is a user-defined value, and does not need to be unique. It is distinct from any execution IDs created or assigned when the job runs. The `Job.Id` is sent in all callback messages. **It is required.** The job ID is commonly used to match a job with a record or entity in an application, such as by setting it to the record's primary key.

#### Job Source

A job's source is the file that all tasks in the job will be performed on. One immutable copy of the source file is made for every Porter job execution, and each tasks uses that copy to do its work. `Source.Mode` is required and indicates the protocol used to fetch the source file. When the mode is set to `S3`, `Source.BucketName` and `Source.ObjectKey` are also required. When the mode is set to `HTTP`, `Source.URL` is also required, which can use either an `http://` or `https://` protocol.

#### Job Tasks

`Tasks` is an array of individual operations the state machine should perform. Every member of the array should be an object with a `Type` property. Valid types are: [`Inspect`](#inspect), [`Copy`](#copy), [`Image`](#image-transform), [`Transcode`](#transcode), [`Transcribe`](#transcribe). Tasks with invalid types are ignored. The other properties of any given task are determined by their type (see below).

#### Job Callbacks

`Callbacks` is an array of endpoints to which callback messages about the job execution will be sent. Each endpoint object has a `Type` (supported types are `AWS/SNS`, `AWS/SQS`, `AWS/S3`, and `HTTP`). Different modes will have additional required properties. `HTTP` callbacks using methods like `POST` or `PUT` require a `Content-Type`. Possible values are `application/json` and `application/x-www-form-urlencoded`.

`AWS/S3` callbacks require both the `BucketName` and `ObjectPrefix` properties. Each callback result will be written to S3 individually (i.e., one file for each task result, and one file for the job result). The object name will be one of the following:

- `[ObjectPrefix][Execution ID]/job_received.json`
- `[ObjectPrefix][Execution ID]/job_result.json`
- `[ObjectPrefix][Execution ID]/task_result.[index].json`

The `ObjectPrefix` property is required, but it can be an empty string, which will result in no prefix being added. An example of a prefix would be `porter_results/`, though the trailing slash is also not required. The `index` value in a task result's file name matches the index of that task from the original job (zero-based numbering). The `Execution ID` is only the final segment of the execution ID ARN.

### Callback Messages

Callback messages are dispatched at various points throughout the execution of a job. Whenever callback messages are sent, messages are always sent to all callbacks defined in the job. Callbacks are optional, and any value in `Job.Callbacks` other than an array will be ignored. Empty arrays are okay.

Each callback includes `Time` and `Timestamp` values. These represent approximately the time at which that specific callback was sent. If multiple callbacks are provided for a job, they may (and likely will) have slightly different timestamps, even though they are sent in parallel. These time values are in addition to the ones included with individual task results, and should always be later (greater than) the task-specific values.

#### Job Received Callbacks

Callbacks are sent when a job has been received (after the input has been normalized). These callbacks will contain a `JobReceived` key.

```json
{
  "Time": "2012-12-21T12:34:56Z",
  "Timestamp": 1356093296.123,
  "JobReceived": {
    "Job": {
      "Id": "1234567890asdfghjkl"
    },
    "Execution": {
      "Id": "arn:aws:states:us-east-1:561178107736:execution:StateMachine-cvPVX5enHWdj:221672a9-ada6-483f-a5a7-ccffd4eee8c5"
    },
    "State": "RECEIVED"
  }
}
```

#### Task Callbacks

Callbacks are sent as individual tasks succeed or fail. For example, if a job includes three `Copy` destinations, a callback will be sent after each copy task completes. (Tasks are processed in parallel, so callbacks may arrive in any order). Task callbacks can be identified by the `TaskResult` key. The original task definition is also included in the callback under the `Task` key.

The JSON message for a successful `Copy` task callback looks like this:

```json
{
    "Time": "2012-12-21T12:34:56Z",
    "Timestamp": 1356093296.123,
    "Task": {
        "Type": "Copy",
        "Mode": "AWS/S3",
        "BucketName": "myBucket",
        "ObjectKey": "myObject.ext"
    },
    "TaskResult": {
        "Job": {
            "Id": "1234567890asdfghjkl"
        },
        "Execution": {
            "Id": "arn:aws:states:us-east-1:561178107736:execution:StateMachine-cvPVX5enHWdj:221672a9-ada6-483f-a5a7-ccffd4eee8c5"
        },
        "Result": {
            "Task": "Copy",
            "Time": "2012-12-21T12:34:50Z",
            "Timestamp": 1356093290.123,
            (Additional task-specific results)
        }
    }
}
```

The JSON message for a failed task will have an `Error` key rather than a `Result` key, like this:

```json
{
  "Time": "2012-12-21T12:34:56Z",
  "Timestamp": 1356093296.123,
  "Task": {
    "Type": "Copy",
    "Mode": "AWS/S3",
    "BucketName": "myBucket",
    "ObjectKey": "myObject.ext"
  },
  "TaskResult": {
    "Job": {
      "Id": "1234567890asdfghjkl"
    },
    "Execution": {
      "Id": "arn:aws:states:us-east-1:561178107736:execution:StateMachine-cvPVX5enHWdj:221672a9-ada6-483f-a5a7-ccffd4eee8c5"
    },
    "Error": {
      "Error": "…",
      "Cause": "…"
    }
  }
}
```

#### Job Result Callback

Callbacks are also sent when the job completes. Job callbacks can be identified by the `JobResult` key. There are three properties that can be inspected to determine the result of the job. All three of these are present for all `JobResult` callbacks; you must check the values, not simply whether the keys exist.

##### Job State

Each job result will include a `State`, which will be one of the following values:

- `"DONE"`
- `"NORMALIZE_INPUT_ERROR"`
- `"SOURCE_FILE_INGEST_ERROR"`
- `"SOURCE_FILE_TYPE_DETECTION_ERROR"`
- `"ITERATOR_ERROR"`

`Done` indicates that the job was able to attempt all the tasks. This is **not** an indication that all the tasks were successful. The other states will appear if an execution step prior to the tasks running fails. `SOURCE_FILE_INGEST_ERROR`, for example, indicates that the artifact copy of the source file couldn't be created.

The list of possible states may change over time.

##### Task Results

`JobResult.TaskResults` is an array of task results for those tasks that completed successfully. If there were no successful tasks in a job, the array will be empty. The data included in a task result is described below for each task type.

##### Failed Task

`JobResult.FailedTasks` is an array of tasks (from the job input) that did not complete successfully. If there were no unsuccessful tasks in a job, the array will be empty.

##### Job Result Examples

Here's an example of a job that had no errors:

```json
{
    "Time": "2012-12-21T12:34:56Z",
    "Timestamp": 1356093296.123,
    "JobResult": {
        "Job": {
            "Id": "1234567890asdfghjkl"
        },
        "Execution": {
            "Id": "arn:aws:states:us-east-1:561178107736:execution:StateMachine-cvPVX5enHWdj:221672a9-ada6-483f-a5a7-ccffd4eee8c5"
        },
        "State": "DONE",
        "FailedTasks": [],
        "TaskResults": [
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

Here's an example of a job that included one successful task and one failed task. Please note that `TaskResults` have a `Task` key, and `TaskErrors` have a `Type` key.

```json
{
    "Time": "2012-12-21T12:34:56Z",
    "Timestamp": 1356093296.123,
    "JobResult": {
        "Job": {
            "Id": "1234567890asdfghjkl"
        },
        "Execution": {
            "Id": "arn:aws:states:us-east-1:561178107736:execution:StateMachine-cvPVX5enHWdj:221672a9-ada6-483f-a5a7-ccffd4eee8c5"
        },
        "State": "DONE",
        "FailedTasks": [
            {
                "Task": "Copy"
                (Additional task-specific results)
            }
        ],
        "TaskResults": [
            {
                "Task": "Copy"
                (Additional task-specific results)
            }
        ]
    }
}
```

This is an example of a job that included two tasks, but whose source file could not be ingested:

```json
{
  "Time": "2012-12-21T12:34:56Z",
  "Timestamp": 1356093296.123,
  "JobResult": {
    "Job": {
      "Id": "1234567890asdfghjkl"
    },
    "Execution": {
      "Id": "arn:aws:states:us-east-1:561178107736:execution:StateMachine-cvPVX5enHWdj:221672a9-ada6-483f-a5a7-ccffd4eee8c5"
    },
    "State": "SOURCE_FILE_INGEST_ERROR",
    "FailedTasks": [],
    "TaskResults": []
  }
}
```

**Example:** If you have a job with three copy tasks, and two callbacks, you would expect to get a total of six `TaskResult` and two `JobResult` messages, across all of the endpoints.

## Serialized Jobs

A job can include any number of additional jobs that will be started after all tasks have succeeded. This allows you to easily perform tasks on files that resulted from an initial job.

As an example, you may have a job with an MP2 source file and a transcode task that produces an MP3 version of that file. You could include a serialized job which then performs a transcribe task on that resulting MP3 file.

Serialized jobs are **not** called recursively as part of the initial job execution. They are simply additional jobs that have their own state machine execution, and are entirely self-contained in their definition and execution. They have their own job ID, source, callbacks, tasks, etc, even additional serialized jobs. There is no inheritance from or referencing to the initial job or its outputs. The only benefit to using serialized jobs is that Porter provides the convenience of starting the job executions for you.

If a job includes any serialized jobs, they are executed after all job result callbacks have been sent. Each serialized job is sent to the SNS topic mentioned previously. As such, the serialized executions are entirely decoupled from the initial execution. It will do nothing to ensure, and have no visibility into, the progress or success of the serialized jobs. Aside from this, including serialized jobs in a job has no impact on the job itself; callbacks will not indicate in any way that a job included serialized jobs, and individual tasks will not be aware of any of the future work that is expected to occur.

When constructing jobs that include serialized jobs, it is constructor's responsibility to build sequential jobs with meaningful values. If the serialized job needs to do work on the result of the initial job's task, the two job definitions must be explicitly constructed in such a way that the resulting file of the task and the source file of the serialized job align.

In some cases it could be acceptable or beneficial for a job and some of its serialized jobs to share a job ID, but this would depend enitrely on how the app that sent the job works, and how it handles the callbacks.

When a job is started via this method, it will include an additional parameter in the definition called `ExecutionTrace`. This is array containing the execution ID of the job that started it, as well as the ID of the job that started that job, etc (if applicable). The last element in the array is the execution ID of the job that started the job being executed.

All jobs included directly as members of `SerializedJobs` are started simultaneously.

```json
{
  "Job": {
    "Id": "1234567890asdfghjkl",
    "Source": {
      "Mode": "AWS/S3",
      "BucketName": "farski-sandbox-prx",
      "ObjectKey": "130224.mp2"
    },
    "SerializedJobs": [
      {
        "Job": {
          "Id": "1234567890asdfghjkl",
          "Source": {
            "Mode": "AWS/S3",
            "BucketName": "farski-sandbox-prx",
            "ObjectKey": "130224.mp2"
          }
        }
      },
      {
        "Job": {
          "Id": "1234567890asdfghjkl",
          "Source": {
            "Mode": "AWS/S3",
            "BucketName": "farski-sandbox-prx",
            "ObjectKey": "130224.mp2"
          }
        }
      }
    ]
  }
}
```

## Tasks

### Copy

`Copy` tasks create copies of the job's source file. Each copy task creates one copy, but a job can include any number of copy tasks. Currently the only supported destination mode is `AWS/S3`. Copy tasks **do not** check if an object already exists in the given location.

The `Time` and `Timestamp` in the output represent approximately when the file finished being copied.

#### AWS/S3

S3 copy operations are done by the [copyObject()](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#copyObject-property) method in the AWS Node SDK. Copying files larger than 5 GB is not supported by the AWS API.

The `BucketName` and `ObjectKey` properties are required.

The default behavior is to preserve all metadata except for the ACL, which is set to private. To set new metadata on the copy, use the optional `Parameters` property on the destination. `MetadataDirective` must be set to `REPLACE` for the operation to honor the new metadate. The contents of `Parameters` are passed directly to the [copyObject()](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#copyObject-property) method.

If you set the optional `ContentType` property to `REPLACE`, the content type of the newly created copy will be set to a [heuristically-determined](https://www.npmjs.com/package/file-type) value. This would replace the content type copied from the source object, if such a value existed. If the content type could not be determined heuristically, this property has no effect. Setting `ContentType` to `REPLACE` will also set `MetadataDirective` to `REPLACE`. If a `ContentType` value is explicitly defined in `Parameters` that value will take precedence.

Input:

```json
{
  "Type": "Copy",
  "Mode": "AWS/S3",
  "BucketName": "myBucket",
  "ObjectKey": "myObject.ext"
}
```

Input with additional parameters:

```json
{
  "Type": "Copy",
  "Mode": "AWS/S3",
  "BucketName": "myBucket",
  "ObjectKey": "myObject.ext",
  "ContentType": "REPLACE",
  "Parameters": {
    "ACL": "public-read",
    "ContentDisposition": "attachment",
    "Metadata": {
      "MyMetadataKey": "MyMetadataValue"
    },
    "MetadataDirective": "REPLACE"
  }
}
```

Output:

```json
{
  "Task": "Copy",
  "BucketName": "myBucket",
  "ObjectKey": "myObject.ext",
  "Time": "2012-12-21T12:34:56Z",
  "Timestamp": 1356093296.123
}
```

### Image Transform

`Image` tasks perform image manipulations on the source file. These are intended for static image files (eg, jpeg, png, webp, gif, svg. Currently the only supported destination mode is `AWS/S3`. A job can include any number of image tasks; each will perform the operation against the original state of the source file.

Resize supports the following parameters: `Fit`, `Height`, `Position`, and `Width`. These follow the same rules as [sharp's](http://sharp.pixelplumbing.com/en/stable/api-resize/#parameters) parameters. The `Resize` property is optional; if excluded the task will not attempt to resize the image. All child properties of the `Resize` object are optional.

`Format` indicates the desired output format. Supported formats are: `jpeg`, `png`, `webp`, and `tiff`. The `Format` property is optional; if excluded the output format will be inferred from the file extension of the destination object.

By default all image metadata (EXIF, XMP, IPTC, etc) is stripped away during processing. If you set `Metadata` to `PRESERVE`, metadata from the input file will be included in the output file. This property is optional, and other values have no effect.

#### AWS/S3

S3 image destinations are done by the [upload()](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#upload-property) method in the AWS Node SDK.

The `BucketName` and `ObjectKey` properties are required.

To set metadata on the new image object, use the optional `Parameters` property on the destination. The contents of `Parameters` are passed directly to the [upload()](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#upload-property) method.

If you set the optional `ContentType` property to `REPLACE`, the content type of the newly created image will be set to a [heuristically-determined](https://www.npmjs.com/package/file-type) value from the job's source file. If the content type could not be determined heuristically, this property has no effect. If a `ContentType` value is explicitly defined in `Parameters` that value will take precedence.

Input:

```json
{
  "Type": "Image",
  "Format": "png",
  "Metadata": "PRESERVE",
  "Resize": {
    "Fit": "cover",
    "Height": 300,
    "Position": "centre",
    "Width": 300
  },
  "Destination": {
    "Mode": "AWS/S3",
    "BucketName": "myBucket",
    "ObjectKey": "myObject.png",
    "ContentType": "REPLACE",
    "Parameters": {
      "ContentDisposition": "attachment",
      "Metadata": {
        "MyMetadataKey": "MyMetadataValue"
      }
    }
  }
}
```

Output:

```json
{
  "Task": "Image",
  "BucketName": "myBucket",
  "ObjectKey": "myObject.ext",
  "Time": "2012-12-21T12:34:56Z",
  "Timestamp": 1356093296.123
}
```

### Transcode

`Transcode` tasks encode and otherwise manipulate the source file. These are intended for audio and video source files, though could operate on any file formats supported by FFmpeg. A job can include any number of transcode tasks; each will perform the operation against the original state of the source file. Currently the only supported destination mode is `AWS/S3`.

A `Format` is required, and is used to explicitly set the output format of the encoding operation; it is not implictly determined by the file extension. The available formats are indicted [in this list](https://johnvansickle.com/ffmpeg/release-readme.txt) with an `E`.

The `FFmpeg` property is optional. When included, each of `GlobalOptions`, `InputFileOptions`, and `OutputFileOptions` properties are also optional. The task constructs a call to FFmpeg that looks like `ffmpeg [global opts] [input file opts] -i input [output file opts] -f [format] output`.

For `AWS/S3` destinations, the contents of `Parameters` are passed directly to the [upload_file()](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/s3.html#S3.Client.upload_file) method as `ExtraArgs`. S3 will default the `content-type` to `binary/octet-stream`, so you may generally want to define that parameter.

Input:

```json
{
  "Type": "Transcode",
  "Format": "flac",
  "FFmpeg": {
    "GlobalOptions": "-loglevel info",
    "InputFileOptions": "-t 500",
    "OutputFileOptions": "-metadata title=some_title"
  },
  "Destination": {
    "Mode": "AWS/S3",
    "BucketName": "myBucket",
    "ObjectKey": "myObject.flac",
    "Parameters": {
      "ContentType": "audio/flac"
    }
  }
}
```

Output:

```json
{
  "Task": "Transcode",
  "BucketName": "myBucket",
  "ObjectKey": "myObject.flac"
}
```

### Inspect

`Inspect` tasks performs an analysis of the job's source file, and returns a set of metadata. The method of analysis and resulting data are determined by the type of the source file.

Input:

```json
{
  "Type": "Inspect"
}
```

Output:

```json
{
    "Task": "Inspect",
    "Inspection": {
        (The results of the analysis.)
    }
}
```

### Transcribe

`Transcribe` tasks use [Amazon Transcribe](https://aws.amazon.com/transcribe/) speech-to-text functionality to generate transcriptions from audio and video files. The artifact must be an mp3, mp4, wav, or flac file for transcriptions to work. The `LanguageCode` property is required. The destination property is required, and the only mode currently supported is `AWS/S3`.

The `MediaFormat` is by default set based on the extension of the source file name. In some cases, you may want to override this to a different valid format by setting the optional `MediaFormat` property of the `Task`. For example if the artifact has an `m4a` extension and the `MediaFormat` should be `mp4`.

Additional transcribe job settings are not supported at this time.

Input:

```json
{
  "Type": "Transcribe",
  "LanguageCode": "en-US",
  "MediaFormat": "mp3",
  "Destination": {
    "Mode": "AWS/S3",
    "BucketName": "myBucket",
    "ObjectKey": "myTranscript.json"
  }
}
```

Output:

```json
{
  "Task": "Transcribe",
  "BucketName": "myBucket",
  "ObjectKey": "myTranscript.json"
}
```

### WAV Wrap

`WavWrap` tasks create a [WAV](https://en.wikipedia.org/wiki/WAV) file from an audio artifact, and apply data to specific chunks of the WAV wrapper.

It accepts MPEG audio files, and any of the chunks supported by [prx-wavefile](https://github.com/PRX/prx-wavefile) including all Broadcast Wave Format chunks and `cart` chunks.

`prx-wavefile` will attempt to set the `fmt`, `mext`, `bext`, `fact`, and `data` chunks from the source file, e.g. analyzing the mpeg audio to set the `fmt` sample rate, bit rate, and number of channels.

The `cart` chunk is optional, and won't be set unless it's included in the `Task.Chunks` array, as in the example below.

The Output includes a `WavfileChunks` array with the attributes set on the `prx-wavefile` chunks.

Input:

```json
{
  "Type": "WavWrap",
  "Destination": {
    "Mode": "AWS/S3",
    "BucketName": "myBucket",
    "ObjectKey": "myTranscript.json"
  },
  "Chunks": [
    {
      "ChunkId": "cart",
      "Version": "0101",
      "CutId": "12345",
      "Title": "Title",
      "Artist": "Artist",
      "StartDate": "2020/01/01",
      "StartTime": "00:00:00",
      "EndDate": "2020/01/14",
      "EndTime": "00:00:00",
      "ProducerAppId": "PRX",
      "ProducerAppVersion": "3.0"
    }
  ]
}
```

Output:

````json
{
  "Task": "WavWrap",
  "Mode": "AWS/S3",
  "BucketName": "myBucket",
  "ObjectKey": "myTranscript.json",
  "Time": "2012-12-21T12:34:56Z",
  "Timestamp": 1356093296.123,
  "WavefileChunks": [
    {
      "chunkId": "cart",
      "chunkSize": 2048,
      "version": "0101",
      "title": "Title",
      "artist": "Artist",
      "cutId": "12345",
      "clientId": "",
      "category": "",
      "classification": "",
      "outCue": "",
      "startDate": "2020/01/01",
      "startTime": "00:00:00",
      "endDate": "2020/01/14",
      "endTime": "10:00:00",
      "producerAppId": "PRX",
      "producerAppVersion": "3.0",
      "userDef": "",
      "levelReference": 0,
      "postTimer": [],
      "reserved": "",
      "url": "",
      "tagText": ""
    }
  ]
}
```

#### AWS/S3

S3 image destinations are done by the [upload()](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#upload-property) method in the AWS Node SDK.

The `BucketName` and `ObjectKey` properties are required.

To set metadata on the new audio file object, use the optional `Parameters` property on the destination. The contents of `Parameters` are passed directly to the [upload()](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#upload-property) method.

If you set the optional `ContentType` property to `REPLACE`, the content type of the newly created image will be set to a [heuristically-determined](https://www.npmjs.com/package/file-type) value from the job's source file. If the content type could not be determined heuristically, this property has no effect. If a `ContentType` value is explicitly defined in `Parameters` that value will take precedence.

## S3 Destination Permissions

Several tasks types produce new files, and [Amazon S3](https://aws.amazon.com/s3/) is a supported destination. When a task includes S3 as a destination, the destination bucket must grant access via its [bucket policy](https://docs.aws.amazon.com/AmazonS3/latest/dev/using-iam-policies.html). Porter creates a IAM role that is always used to perform S3 actions on destination buckets, so the bucket policies must allow the necessary actions for that policy. The role's ARN is published as an output on the CloudFormation stack.

The following is an example of the bucket policy used for granting Porter access to a bucket called `myBucket`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123456789012:role/porter-prod-S3DestinationWriterRole-TKTKTKTKTK"
      },
      "Action": "s3:ListBucketMultipartUploads",
      "Resource": "arn:aws:s3:::myBucket"
    },
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123456789012:role/porter-prod-S3DestinationWriterRole-TKTKTKTKTK"
      },
      "Action": [
        "s3:PutObject*",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": "arn:aws:s3:::myBucket/*"
    }
  ]
}
````

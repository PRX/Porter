# Rexif

tktktk

## Messaging I/O

Rexif receives messages to start jobs, and sends messages while jobs are running, and when jobs complete or fail.

### Starting a Job

When you want to start a job, a message must be sent to Rexif. This can be done either directly through the [AWS Step Functions API](https://docs.aws.amazon.com/step-functions/latest/apireference/Welcome.html), or by way of an SNS topic that is created along side the state machine when the CloudFormation stack is launched.

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
            "URI": "https://example.com/audioFile.wav"
        },
        "Inspect": {
            "Perform": true
        },
        "Copy": {
            "Destinations": [
                {
                    "Mode": "S3",
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
                        "Mode": "S3",
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

`Source.URI` is required and points to the file that the job will process. The following protocols are supported: `http://`, `https://`, `s3://`.

`Inspect`, `Copy`, and `Transcode` are the various tasks that can be run during a job execution. Each task type will have its own format.

`Callbacks` is an array of endpoints to which callback messages about the job execution will be sent. Each endpoint object has a `Mode` (supported modes are `AWS/SNS`, `AWS/SQS`, and `HTTP`). Different modes will have additional required properties. (HTTP callbacks will **not** follow redirects.)

### Callback Messages

Callback messages are dispatched at various points throughout the execution of a job. Whenever callback messages are sent, messages are always sent to all callbacks defined in the job. Callbacks are optional, and any value in `Job.Callbacks` other than an array will be ignored. Empty arrays are okay.

Callbacks are sent as individual tasks are completed. For example, if a job includes three `Copy` destinations, a callback will be sent after each copy task completes. (Tasks are processed in parallel, so callbacks may arrive in any order). Task callbacks can be identified by the `TaskResult` key. The JSON message for a `Copy` task callback looks like this:

```
{
    "TaskResult": {
        "Job": {
            "Id": "1234567890asdfghjkl"
        },
        "Execution": {
            "Id": "arn:aws:states:us-east-1:561178107736:execution:StateMachine-cvPVX5enHWdj:221672a9-ada6-483f-a5a7-ccffd4eee8c5"
        },
        "Result": {
            "Task": "Copy"
            (Additional task-specific results)
        }
    }
}
```

> Note: If an individual task fails, there is no task-level error callback that gets sent. A failure in any part of the state machine will cause the entire state machine to fail, and the error will be reported in the job error callback.

Callbacks are also sent when the job completes. Job callbacks can be identified by the `JobResult` key. The callback message includes information about all tasks that were completed. When the job was successful, the `JobResult` object will include a `Result` key.

```
{
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

## Tasks

### Copy

`Copy` tasks create copies of the job's source file at locations in S3 defined on the task. The locations are declared as `Destinations`. Currently the only supported destination mode is `S3`. Copy tasks **do not** check if an object already exists in the given location. The copy operation is done by the [copyObject()](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#copyObject-property) method in the AWS Node SDK. A copy task can include any number of destinations.

If `Job.Copy.Destinations` is not an array with at least one element, the state machine will act as though no copy tasks were included in the job.

Input:

```
{
    "Copy": {
        "Destinations": [
            {
                "Mode": "S3",
                "BucketName": "myBucket",
                "ObjectKey": "myObject.ext"
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
    "ObjectKey": "myObject.ext"
}
```

### Transcode

`Transcode` tasks encode and otherwise manipulate the source file. These are intended for audio and video source files. The desired transcoding are declared as `Encodings`, and each encoding includes the properties of the output file, and a single destination for the output file to be sent to. A transcode task can include any number of encodings.

If `Job.Transcode.Encodings` is not an array with at least one element, the state machine will act as though no copy tasks were included in the job.

Input:

```
{
    "Transcode": {
        "Encodings": [
            {
                "Format": "flac",
                "Destination": {
                    "Mode": "S3",
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

### Inspect

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

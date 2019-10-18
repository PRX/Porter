# Refix

#### Useful Resources

- [AWS Step Functions Developer Guide](https://docs.aws.amazon.com/step-functions/latest/dg/welcome.html)

### TKTKTK

There are a number of shell scripts in this repo. They assume you have a profile in `~/.aws/config` called `prx_legacy`, which is configured to access the `prx-legacy` AWS account.



## Internal Messaging

How data is passed between the various states of the Step Function is important predictable and reliable executions. The following is a detailed look at the lifecycle of inputs and outputs of the state machine internals. The code examples are meant to demonstrate important structural aspects, and are not necessarily 100% accurate.

In some cases, states will use a result path of `$.Void` if their return values are unwanted. These are treated in the documentation below as though they don't exist.

### Execution Input

This is the input provided by the end user as raw JSON. The format is covered in detail in the [README](README.md). `Job.Id` and `Job.Source` are consider required.

```
{ "Job": { "Id": "1234567890asdfghjkl", "Source": { "Mode": "AWS/S3" } } }
```

###

### Input Normalization

In order to allow for optional values in the input format (i.e., allow some properties to be excluded), the input is normalized at the beginning of the execution. This allows later states to assume that certain values exist in their inputs, since in general states will fail if they try to access missing values.

This state does no input or output processing. It takes in the complete execution input, passes the entire input to the Lambda function, and uses the result of the Lambda function as the entire output result.

- `InputPath`: `$`, `{ Job: { … } }`
- `Parameters`: n/a, `{ Job: { … } }`
- `ResultPath`: `$`, `{ Job: { … } }`
- `OutputPath`: `$`, `{ Job: { … } }`

### Job Received Callbacks

Callback I/O is covered in detail later. This step should have no impact on

### Ingest Source File

The Ingest function relies on the `Job.Source` data. It also uses the Step Function execution ID to isolate work it's doing. The entire input must remain available to later states, so there's no `InputPath`. The necessary data is passed to the Lambda function as `Parameters`, including the interpolated execution ID.

The result of the Lambda function is inserted into the output under the `Artifact` property, and the entire output (the input with the `Artifact`) is passed to the next state.

- `InputPath`: `$`, `{ Job: { … } }`
- `Parameters`: `{ Job: { Source }, Execution: { Id }}`
- `ResultPath`: `".Artifact`, `{ Job: { … }, Artifact: { … } }`
- `OutputPath`: `$`, `{ Job: { … }, Artifact: { … } }`

### Source File Type Detection

This Lambda function requires only the `Artifact` from the input, but as before the entire input must be maintained in the output.

The output of the Lambda function is added to the `Artifact` property under the `Descriptor` key, and the entire output (the input with the amended `Artifact`) is passed to the next state.

- `InputPath`: `$`, `{ Job: { … }, Artifact: { … } }`
- `Parameters`: `{ Arifact: {} }`
- `ResultPath`: `".Artifact.Descriptor`, `{ Job: { … }, Artifact: { … } }`
- `OutputPath`: `$`, `{ Job: { … }, Artifact: { … } }`

### Job Tasks

This is a parallel state that included branches for all the distinct tasks that can be performed. The results are mapped to `JobTaskResults`, and is array whose elements are the results of each branch.

- `InputPath`: `$`, `{ Job: { … }, Artifact: { … } }`
- `Parameters`: n/a
- `ResultPath`: `"$.JobTaskResults`, `{ Job: { … }, Artifact: { … }, JobTaskResults: { … } }`
- `OutputPath`: `$`, `{ Job: { … }, Artifact: { … }, JobTaskResults: [ … ] }`


### Execution Output

The state machine's output is `[]`. This is entirely distinct from the messaging format of callbacks.

// Various states in the machine will expect that specific keys always exist in
// their input (e.g., Copy tasks will always expect $.Job.Copy.Destinations to
// exist). In order to allow for input to the state machine that does not
// strictly require all keys that any part of the machine may require, this
// function ensures that any input keys required during the execution of the
// Step Function exist, regardless of if they exist in the original message.
//
// The input to this function is the original input to the execution of the
// state machine under the `input` key, plus some additional data, such as
// state machine metadata.
//
// The function returns the normalized Input.
//
// The result path and output path MUST both be "$".

exports.handler = async (event) => {
  // This is the raw Step Functions execution input
  const { Input } = event;

  console.log(JSON.stringify({ msg: 'Unmodified input', event }));

  // Set Job.Tasks to an empty array, unless it's already an array.
  if (
    !Object.prototype.hasOwnProperty.call(Input.Job, 'Tasks') ||
    !Array.isArray(Input.Job.Tasks)
  ) {
    Input.Job.Tasks = [];
  }

  // Make sure all Transcode tasks have all three FFmpeg options
  Input.Job.Tasks.forEach((task) => {
    // The state machine definition expects each task to have a Type property,
    // and fails without the error being caught if it's missing. This forces
    // the execution to error out in a way that can be caught and handled as
    // expected. (Choice states don't support Catch)
    if (!Object.prototype.hasOwnProperty.call(task, 'Type')) {
      throw new Error('Job included a task without a Type');
    }

    if (task.Type !== 'Transcode') {
      return;
    }

    if (!Object.prototype.hasOwnProperty.call(task, 'FFmpeg')) {
      task.FFmpeg = {};
    }
    if (!Object.prototype.hasOwnProperty.call(task.FFmpeg, 'GlobalOptions')) {
      task.FFmpeg.GlobalOptions = '';
    }
    if (
      !Object.prototype.hasOwnProperty.call(task.FFmpeg, 'InputFileOptions')
    ) {
      task.FFmpeg.InputFileOptions = '';
    }
    if (
      !Object.prototype.hasOwnProperty.call(task.FFmpeg, 'OutputFileOptions')
    ) {
      task.FFmpeg.OutputFileOptions = '';
    }
  });

  // Set Job.Callbacks to an empty array, unless it's already an array.
  if (
    !Object.prototype.hasOwnProperty.call(Input.Job, 'Callbacks') ||
    !Array.isArray(Input.Job.Callbacks)
  ) {
    Input.Job.Callbacks = [];
  }

  // Set Job.SerializedJobs to an empty array, unless it's already an array.
  if (
    !Object.prototype.hasOwnProperty.call(Input.Job, 'SerializedJobs') ||
    !Array.isArray(Input.Job.SerializedJobs)
  ) {
    Input.Job.SerializedJobs = [];
  }

  // Set Job.ExecutionTrace to an empty array, unless it's already an array.
  if (
    !Object.prototype.hasOwnProperty.call(Input.Job, 'ExecutionTrace') ||
    !Array.isArray(Input.Job.ExecutionTrace)
  ) {
    Input.Job.ExecutionTrace = [];
  }

  console.log(JSON.stringify({ msg: 'Normalized input', Input }));

  // These values are required to exist in the state machine definition at some
  // point, but are not guaranteed to be inserted during every execution, so
  // we pre-create them now to be safe.
  Input.State = 'DONE';

  return Input;
};

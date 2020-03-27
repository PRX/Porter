// Various states in the machine will expect that specific keys always exist in
// their input (e.g., Copy tasks will always expect $.Job.Copy.Destinations to
// exist). In order to allow for input to the state machine that does not
// strictly require all keys that any part of the machine may require, this
// function ensures that any input keys required during the execution of the
// Step Function exist, regardless of if they exist in the original message.
//
// The input to this function is the original input to the execution of the
// state machine, and the input path MUST be that entire input (i.e., "$").
//
// The function returns the input, plus any required values that were missing.
//
// The result path and output path MUST both be "$".

exports.handler = async (event) => {
  console.log(JSON.stringify({ msg: 'Unmodified input', event: event }));

  // Set Job.Tasks to an empty array, unless it's already an array.
  if (!event.Job.hasOwnProperty('Tasks') || !Array.isArray(event.Job.Tasks)) {
    event.Job.Tasks = [];
  }

  // Make sure all Transcode tasks have all three FFmpeg options
  event.Job.Tasks.forEach((task) => {
    // The state machine definition expects each task to have a Type property,
    // and fails without the error being caught if it's missing. This forces
    // the execution to error out in a way that can be caught and handled as
    // expected. (Choice states don't support Catch)
    if (!task.hasOwnProperty('Type')) { throw new Error('Job included a task without a Type'); }

    if (task.Type !== 'Transcode') { return; }

    if (!task.hasOwnProperty('FFmpeg')) { task.FFmpeg = {}; }
    if (!task.FFmpeg.hasOwnProperty('GlobalOptions')) { task.FFmpeg.GlobalOptions = ''; }
    if (!task.FFmpeg.hasOwnProperty('InputFileOptions')) { task.FFmpeg.InputFileOptions = ''; }
    if (!task.FFmpeg.hasOwnProperty('OutputFileOptions')) { task.FFmpeg.OutputFileOptions = ''; }
  });

  // Set Job.Callbacks to an empty array, unless it's already an array.
  if (!event.Job.hasOwnProperty('Callbacks') || !Array.isArray(event.Job.Callbacks)) {
    event.Job.Callbacks = [];
  }

  // Set Job.SerializedJobs to an empty array, unless it's already an array.
  if (!event.Job.hasOwnProperty('SerializedJobs') || !Array.isArray(event.Job.SerializedJobs)) {
    event.Job.SerializedJobs = [];
  }

  // Set Job.ExecutionTrace to an empty array, unless it's already an array.
  if (!event.Job.hasOwnProperty('ExecutionTrace') || !Array.isArray(event.Job.ExecutionTrace)) {
    event.Job.ExecutionTrace = [];
  }

  console.log(JSON.stringify({ msg: 'Normalized input', event: event }));

  // These values are required to exist in the state machine definition at some
  // point, but are not guaranteed to be inserted during every execution, so
  // we pre-create them now to be safe.
  event.State = "DONE";

  return event;
};

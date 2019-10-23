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

  // The Inspect task has no other options, so if it's expected to run it
  // would explicitly set Perform to true. Anything else is forced to false
  try {
    if (typeof event.Job.Inspect.Perform !== 'boolean') {
      event.Job.Inspect = { Perform: false };
    }
  } catch (error) {
    event.Job.Inspect = { Perform: false };
  }

  // The Copy task expects an array of Destinations that isn't empty. Anything
  // else results in the Copy task being disabled (Perform = false)
  try {
    if (Array.isArray(event.Job.Copy.Destinations)
        && event.Job.Copy.Destinations.length > 0) {
      event.Job.Copy.Perform = true;
    } else {
      event.Job.Copy = { Perform: false };
    }
  } catch (error) {
    event.Job.Copy = { Perform: false };
  }

  // The Transcode task expects an array of Encodings that isn't empty.
  // Anything else results in the Transcode task being disabled (Perform = false)
  try {
    if (Array.isArray(event.Job.Transcode.Encodings)
        && event.Job.Transcode.Encodings.length > 0) {
      event.Job.Transcode.Perform = true;
    } else {
      event.Job.Transcode = { Perform: false };
    }
  } catch (error) {
    event.Job.Transcode = { Perform: false };
  }

  // The Image task expects an array of Transforms that isn't empty.
  // Anything else results in the Image task being disabled (Perform = false)
  try {
    if (Array.isArray(event.Job.Image.Transforms)
        && event.Job.Image.Transforms.length > 0) {
      event.Job.Image.Perform = true;
    } else {
      event.Job.Image = { Perform: false };
    }
  } catch (error) {
    event.Job.Image = { Perform: false };
  }

  // Set Job.Callbacks to an empty array, unless it's already an array.
  if (!event.Job.hasOwnProperty('Callbacks') || !Array.isArray(event.Job.Callbacks)) {
    event.Job.Callbacks = [];
  }

  console.log(JSON.stringify({ msg: 'Normalized input', event: event }));

  return event;
}

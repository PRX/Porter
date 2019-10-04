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
// The function return the input, plus any required values that were missing.
//
// The result path and output path MUST both be "$".

exports.handler = async (event) => {
  try {
    if (typeof event.Job.Inspect.Perform !== 'boolean') {
      event.Job.Inspect = { Perform: false };
    }
  } catch (error) {
    event.Job.Inspect = { Perform: false };
  }

  try {
    if (event.Job.Copy.Destinations.length > 0) {
      event.Job.Copy.Perform = true;
    } else {
      event.Job.Copy = { Perform: false };
    }
  } catch (error) {
    event.Job.Copy = { Perform: false };
  }

  // Ensure that
  try {
    if (event.Job.Copy.Encodings.length > 0) {
      event.Job.Transcode.Perform = true;
    } else {
      event.Job.Transcode = { Perform: false };
    }
  } catch (error) {
    event.Job.Transcode = { Perform: false };
  }

  // Set Job.Callbacks to an empty array, unless it's already an array.
  if (!event.Job.hasOwnProperty('Callbacks') || !Array.isArray(event.Job.Callbacks)) {
    event.Job.Callbacks = [];
  }

  return event;
}

// Because the result of a Fargate task is not sufficient for sending a proper
// callback, this function takes the entire task input and builds a better
// result that gets passed to the callback task.

exports.handler = async (event) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

    const result = {
      Task: event.Task.Type,
      BucketName: event.Task.Destination.BucketName,
      ObjectKey: event.Task.Destination.ObjectKey,
    }

  console.log(JSON.stringify({ msg: 'Result', result: result }));

  return result;
}

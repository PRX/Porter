// To make it easier to pass large, arbitrary sets of data to the Fargate
// environment, some aspects of the Task input a serialized to JSON and added
// to the state data.

exports.handler = async (event) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  const result = {
    Destination: JSON.stringify(event.Task.Destination),
  };

  console.log(JSON.stringify({ msg: 'Result', result }));

  return result;
};

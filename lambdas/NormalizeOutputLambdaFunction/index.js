// Returns a value that should be identical to the JobResults message
// that is sent with job callbacks.

exports.handler = async (event) => {
  console.log(JSON.stringify({ msg: 'State input', event: event }));

  const now = new Date;
  const msg = { Time: now.toISOString(), Timestamp: (now / 1000) };

  if (event.Message) { Object.assign(msg, event.Message); }

  console.log(JSON.stringify({ msg: 'Normalized output', body: msg }));

  return msg;
}

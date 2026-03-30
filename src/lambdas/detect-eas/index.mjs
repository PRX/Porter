export const handler = async (event, context) => {
  console.log(JSON.stringify({ msg: "State input", input: event }));
};

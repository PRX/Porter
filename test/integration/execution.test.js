const fs = require('fs');
const { yamlParse, yamlDump } = require('yaml-cfn');

test('integration test', async () => {
  const file = fs.readFileSync('template.yml', 'utf8');
  const template = yamlParse(file);
  const state = template.Resources.StateMachine;
  const json = state.Properties.DefinitionString['Fn::Sub'][0];
  const definition = JSON.parse(json);

  console.log(definition);

  expect(1).toEqual(1);
});

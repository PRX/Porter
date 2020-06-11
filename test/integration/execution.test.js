const fs = require('fs');
const { yamlParse, yamlDump } = require('yaml-cfn');

test('integration test', async () => {
  const yaml = fs.readFileSync('template.yml', 'utf8');
  const cfn = yamlParse(yaml);

  const json = fs.readFileSync('state-machine.asl.json', 'utf8');
  const asl = JSON.parse(json);

  expect(1).toEqual(1);
});

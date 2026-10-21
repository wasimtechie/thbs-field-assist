import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';

// Public synthetic fixture only. Never include this test config in a demo build.
mkdirSync('.local', {recursive: true});
const schema = readFileSync('fixtures/templates/fibre-cable-label.json');
writeFileSync('.local/cable-native-test-config.json', JSON.stringify({
  CABLE_LABEL_TEST_SCHEMA_BASE64: schema.toString('base64'),
}) + '\n', {mode: 0o600});
console.log('Prepared synthetic cable-label native test configuration.');

// Shared emulator test-environment setup for the rules test suites.
// Run only via test/rules/run.sh, inside `firebase emulators:exec`, which
// sets FIRESTORE_EMULATOR_HOST / FIREBASE_STORAGE_EMULATOR_HOST — but we also
// pass explicit host/port matching firebase.json so the tests are correct
// even if invoked some other way against a manually started emulator pair.
const fs = require('fs');
const path = require('path');
const { initializeTestEnvironment } = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'taskmaster-app-3d480';
const REPO_ROOT = path.resolve(__dirname, '../..');

async function makeTestEnv() {
  return initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(path.join(REPO_ROOT, 'firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
    storage: {
      rules: fs.readFileSync(path.join(REPO_ROOT, 'storage.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 9199,
    },
  });
}

module.exports = { PROJECT_ID, makeTestEnv };

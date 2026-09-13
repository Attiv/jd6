const { execSync } = require('child_process');
const fs = require('fs');

const adb = '/Users/mac/Library/Android/sdk/platform-tools/adb';

// Write a shell script on device to check /data/data/com.vitta.xmjd/files/rime
try {
  // Let's see if adb backup or adb shell cmd package or pm path works
  const res = execSync(`${adb} shell "ls -la /sdcard/Android/data/com.vitta.xmjd/files/ ; ls -la /sdcard/Android/data/com.vitta.xmjd/"`, { encoding: 'utf-8' });
  fs.writeFileSync('output_test.txt', res);
} catch (e) {
  fs.writeFileSync('output_test.txt', `ERR: ${e.message}\n${e.stdout}\n${e.stderr}`);
}

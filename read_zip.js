const fs = require('fs');
const zlib = require('zlib');
const { execSync } = require('child_process');
const adb = '/Users/mac/Library/Android/sdk/platform-tools/adb';

// Inspect xmjd.zip entries
try {
  const buf = fs.readFileSync('/Users/mac/AndroidStudioProjects/xmjd/app/src/main/assets/xmjd.zip');
  let i = 0;
  const files = [];
  while (i < buf.length - 4) {
    if (buf[i] === 0x50 && buf[i+1] === 0x4b && buf[i+2] === 0x01 && buf[i+3] === 0x02) {
      const fnLen = buf.readUInt16LE(i + 28);
      const extraLen = buf.readUInt16LE(i + 30);
      const commentLen = buf.readUInt16LE(i + 32);
      const fn = buf.toString('utf8', i + 46, i + 46 + fnLen);
      files.push(fn);
      i += 46 + fnLen + extraLen + commentLen;
    } else {
      i++;
    }
  }
  fs.writeFileSync('xmjd_zip_files.txt', files.join('\n'));
} catch (e) {
  fs.writeFileSync('xmjd_zip_files.txt', `ERR: ${e.message}`);
}

// Inspect phone diagnostics via adb
try {
  const res = execSync(`${adb} logcat -d -b main -b events -b crash -b system`, { encoding: 'utf-8', maxBuffer: 50 * 1024 * 1024 });
  const lines = res.split('\n').filter(l => l.includes('6124') || l.includes('XMJD') || l.includes('Rime') || l.includes('rime'));
  fs.writeFileSync('phone_full_log.txt', lines.join('\n'));
} catch (e) {
  fs.writeFileSync('phone_full_log.txt', `ERR: ${e.message}`);
}


#!/usr/bin/env node
'use strict';

const fs = require('fs');

function usage() {
  console.log('Usage: node decode_pcm_to_wav.js --input response.json --output output.wav');
}

function getArg(flag) {
  const idx = process.argv.indexOf(flag);
  if (idx === -1) return '';
  return process.argv[idx + 1] || '';
}

if (process.argv.includes('--help') || process.argv.includes('-h')) {
  usage();
  process.exit(0);
}

const inputPath = getArg('--input') || 'response.json';
const outputPath = getArg('--output') || 'output.wav';

if (!fs.existsSync(inputPath)) {
  console.error(`Input file not found: ${inputPath}`);
  process.exit(1);
}

let response;
try {
  response = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
} catch (error) {
  console.error(`Failed to parse JSON: ${error.message}`);
  process.exit(1);
}

const part =
  response?.candidates?.[0]?.content?.parts?.find(
    (candidate) => candidate?.inlineData?.data && candidate?.inlineData?.mimeType
  ) || null;

if (!part) {
  console.error('Audio data not found in response JSON.');
  process.exit(1);
}

const base64Audio = part.inlineData.data;
const mimeType = String(part.inlineData.mimeType || 'audio/L16;rate=24000');
const match = mimeType.match(/rate=(\d+)/i);
const sampleRate = match ? Number(match[1]) : 24000;

const bitsPerSample = 16;
const numChannels = 1;
const pcmBuffer = Buffer.from(base64Audio, 'base64');

if (pcmBuffer.length === 0) {
  console.error('Decoded PCM buffer is empty.');
  process.exit(1);
}

const byteRate = sampleRate * numChannels * (bitsPerSample / 8);
const blockAlign = numChannels * (bitsPerSample / 8);
const dataSize = pcmBuffer.length;

const header = Buffer.alloc(44);
header.write('RIFF', 0);
header.writeUInt32LE(36 + dataSize, 4);
header.write('WAVE', 8);
header.write('fmt ', 12);
header.writeUInt32LE(16, 16);
header.writeUInt16LE(1, 20);
header.writeUInt16LE(numChannels, 22);
header.writeUInt32LE(sampleRate, 24);
header.writeUInt32LE(byteRate, 28);
header.writeUInt16LE(blockAlign, 32);
header.writeUInt16LE(bitsPerSample, 34);
header.write('data', 36);
header.writeUInt32LE(dataSize, 40);

const wavBuffer = Buffer.concat([header, pcmBuffer]);
fs.writeFileSync(outputPath, wavBuffer);

console.log(`WAV saved: ${outputPath}`);

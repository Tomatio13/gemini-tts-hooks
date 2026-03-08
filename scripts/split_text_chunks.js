#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

function usage() {
  console.log('Usage: node split_text_chunks.js --input-file input.txt --max-chars 300 --output-dir /tmp/chunks');
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

const inputFile = getArg('--input-file');
const outputDir = getArg('--output-dir');
const maxChars = Number(getArg('--max-chars') || '0');

if (!inputFile || !outputDir || !Number.isFinite(maxChars) || maxChars <= 0) {
  usage();
  process.exit(1);
}

if (!fs.existsSync(inputFile)) {
  console.error(`Input file not found: ${inputFile}`);
  process.exit(1);
}

const rawText = fs.readFileSync(inputFile, 'utf8');
const text = rawText.replace(/\r\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();

if (!text) {
  console.error('Input text is empty.');
  process.exit(1);
}

function splitSentences(src) {
  const units = src.match(/[^。！？\n]+[。！？\n]?/g) || [];
  return units.map((unit) => unit.trim()).filter(Boolean);
}

function splitOverLimit(sentence, limit) {
  if (sentence.length <= limit) return [sentence];

  const pieces = [];
  let rest = sentence;

  while (rest.length > limit) {
    const window = rest.slice(0, limit);
    const punctIdx = Math.max(
      window.lastIndexOf('、'),
      window.lastIndexOf('，'),
      window.lastIndexOf(','),
      window.lastIndexOf('；'),
      window.lastIndexOf(';'),
      window.lastIndexOf(' ')
    );

    const cutAt = punctIdx >= Math.floor(limit * 0.5) ? punctIdx + 1 : limit;
    pieces.push(rest.slice(0, cutAt).trim());
    rest = rest.slice(cutAt).trim();
  }

  if (rest) pieces.push(rest);
  return pieces.filter(Boolean);
}

const sentences = splitSentences(text);
const normalizedUnits = [];
for (const sentence of sentences) {
  normalizedUnits.push(...splitOverLimit(sentence, maxChars));
}

const chunks = [];
let current = '';

for (const unit of normalizedUnits) {
  if (!current) {
    current = unit;
    continue;
  }

  if ((current + unit).length <= maxChars) {
    current += unit;
  } else {
    chunks.push(current);
    current = unit;
  }
}

if (current) chunks.push(current);

fs.mkdirSync(outputDir, { recursive: true });

chunks.forEach((chunk, index) => {
  const filename = `chunk_${String(index + 1).padStart(3, '0')}.txt`;
  fs.writeFileSync(path.join(outputDir, filename), chunk);
});

console.log(chunks.length);

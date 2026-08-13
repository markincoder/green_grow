#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const webpush = require('web-push');

const dataDir = process.env.DATA_DIR || path.join(__dirname, '..', 'data');
fs.mkdirSync(dataDir, { recursive: true });
const out = path.join(dataDir, 'vapid.json');

if (fs.existsSync(out)) {
  console.log('Already exists:', out);
  process.exit(0);
}

const keys = webpush.generateVAPIDKeys();
const payload = {
  publicKey: keys.publicKey,
  privateKey: keys.privateKey,
  subject: process.env.VAPID_SUBJECT || 'mailto:support@agronizer.ru',
};
fs.writeFileSync(out, JSON.stringify(payload, null, 2));
console.log('Wrote', out);
console.log('publicKey:', keys.publicKey);

'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const http = require('node:http');

delete process.env.REDIS_URL;

const legalRouter = require('../src/routes/legal');

function startServer() {
  const app = express();
  app.use('/legal', legalRouter);
  const server = http.createServer(app);
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}

function request(port, path) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, path, method: 'GET' }, (res) => {
      let body = '';
      res.setEncoding('utf-8');
      res.on('data', (c) => (body += c));
      res.on('end', () => resolve({ status: res.statusCode, body }));
    });
    req.on('error', reject);
    req.end();
  });
}

test('несуществующий документ отдаёт 404', async () => {
  const server = await startServer();
  try {
    const { port } = server.address();
    const res = await request(port, '/legal/nope');
    assert.equal(res.status, 404);
  } finally {
    server.close();
  }
});

test('свойства прототипа Object не считаются документами (404, а не 500)', async () => {
  const server = await startServer();
  try {
    const { port } = server.address();
    const probes = ['constructor', 'toString', 'valueOf', 'hasOwnProperty', '__proto__'];
    const statuses = [];
    for (const probe of probes) {
      const res = await request(port, `/legal/${encodeURIComponent(probe)}`);
      statuses.push([probe, res.status]);
    }
    assert.deepEqual(
      statuses,
      probes.map((p) => [p, 404]),
      'DOCUMENTS[req.params.document] находит унаследованные свойства: meta truthy, meta.file undefined, path.join бросает TypeError -> 500'
    );
  } finally {
    server.close();
  }
});

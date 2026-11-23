const express = require('express');
const os = require('os');
const path = require('path');
const { MongoClient } = require('mongodb');

const MONGO_URL = process.env.MONGO_URL;
if (!MONGO_URL) {
  console.error('FATAL: MONGO_URL environment variable is not set');
  process.exit(1);
}
const PORT = process.env.PORT || 3000;
const POD_NAME = process.env.HOSTNAME || os.hostname();

function getPodIp() {
  for (const list of Object.values(os.networkInterfaces())) {
    for (const nic of list) {
      if (nic.family === 'IPv4' && !nic.internal) return nic.address;
    }
  }
  return '127.0.0.1';
}
const POD_IP = getPodIp();

const client = new MongoClient(MONGO_URL, { serverSelectionTimeoutMS: 3000 });
const calculations = () => client.db().collection('calculations');

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

function parsePositive(value) {
  if (value === '' || value === null || value === undefined) return NaN;
  const num = Number(value);
  return Number.isFinite(num) && num > 0 ? num : NaN;
}

app.post('/api/emi', async (req, res) => {
  const P = parsePositive(req.body.P);
  const rate = parsePositive(req.body.rate);
  const n = parsePositive(req.body.n);
  if (Number.isNaN(P) || Number.isNaN(rate) || Number.isNaN(n) || !Number.isInteger(n)) {
    return res.status(400).json({ error: 'P, rate and n must be positive numbers (n a whole number of months)' });
  }
  const r = rate / 12 / 100;
  const factor = Math.pow(1 + r, n);
  const emi = (P * r * factor) / (factor - 1);
  if (!Number.isFinite(emi)) {
    return res.status(400).json({ error: 'Inputs are too large to calculate' });
  }
  const round2 = (x) => Math.round(x * 100) / 100;
  const result = {
    emi: round2(emi),
    totalPayment: round2(emi * n),
    totalInterest: round2(emi * n - P),
    servedBy: POD_NAME,
    podIp: POD_IP,
  };
  try {
    await calculations().insertOne({
      principal: P,
      rate: rate,
      months: n,
      emi: result.emi,
      servedBy: POD_NAME,
      createdAt: new Date(),
    });
  } catch (err) {
    console.error('DB write failed:', err.message);
    return res.status(503).json({ error: 'Database unavailable' });
  }
  res.json(result);
});

app.get('/api/history', async (req, res) => {
  try {
    const rows = await calculations()
      .find({}, { projection: { _id: 0 } })
      .sort({ createdAt: -1 })
      .limit(10)
      .toArray();
    res.json(rows);
  } catch (err) {
    console.error('DB read failed:', err.message);
    res.status(503).json({ error: 'Database unavailable' });
  }
});

app.get('/health', async (req, res) => {
  try {
    await client.db().command({ ping: 1 });
    res.status(200).send('OK');
  } catch (err) {
    res.status(503).send('MongoDB unreachable');
  }
});

app.listen(PORT, () => console.log(`EMI app on port ${PORT}, pod=${POD_NAME}, ip=${POD_IP}`));

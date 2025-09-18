const express = require('express');
const cors = require('cors');
const axios = require('axios');
const path = require('path');

const app = express();
const port = process.env.PORT || 3002;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Aggregation service URL
const AGGREGATION_SERVICE_URL = process.env.AGGREGATION_SERVICE_URL || 'http://aggregation-service:3000';

// Proxy endpoints to aggregation service
app.get('/api/health', async (req, res) => {
  try {
    const response = await axios.get(`${AGGREGATION_SERVICE_URL}/health`);
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: 'Failed to connect to aggregation service' });
  }
});

app.get('/api/stats', async (req, res) => {
  try {
    const response = await axios.get(`${AGGREGATION_SERVICE_URL}/stats`);
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch stats' });
  }
});

app.get('/api/customers', async (req, res) => {
  try {
    const response = await axios.get(`${AGGREGATION_SERVICE_URL}/customers`, {
      params: req.query
    });
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch customers' });
  }
});

app.get('/api/customers/:id', async (req, res) => {
  try {
    const response = await axios.get(`${AGGREGATION_SERVICE_URL}/customers/${req.params.id}`);
    res.json(response.data);
  } catch (error) {
    if (error.response?.status === 404) {
      res.status(404).json({ error: 'Customer not found' });
    } else {
      res.status(500).json({ error: 'Failed to fetch customer' });
    }
  }
});

// Serve the main HTML file
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(port, '0.0.0.0', () => {
  console.log(`Analytics UI server running on port ${port}`);
});

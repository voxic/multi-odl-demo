const express = require('express');
const cors = require('cors');
const axios = require('axios');
const path = require('path');

const app = express();
const port = process.env.PORT || 3003;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Customer profile service URL
const CUSTOMER_PROFILE_SERVICE_URL = process.env.CUSTOMER_PROFILE_SERVICE_URL || 'http://customer-profile-service:3001';

// Proxy endpoints to customer profile service
app.get('/health', async (req, res) => {
  try {
    const response = await axios.get(`${CUSTOMER_PROFILE_SERVICE_URL}/health`);
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: 'Failed to connect to customer profile service' });
  }
});

app.get('/api/health', async (req, res) => {
  try {
    const response = await axios.get(`${CUSTOMER_PROFILE_SERVICE_URL}/health`);
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: 'Failed to connect to customer profile service' });
  }
});

app.get('/api/customers/random', async (req, res) => {
  try {
    const response = await axios.get(`${CUSTOMER_PROFILE_SERVICE_URL}/api/customers/random`);
    res.json(response.data);
  } catch (error) {
    console.error('Error fetching random customer:', error);
    if (error.response?.status === 404) {
      res.status(404).json({ error: 'No customer profiles found' });
    } else {
      res.status(500).json({ error: 'Failed to fetch random customer' });
    }
  }
});

app.get('/api/customers/:id', async (req, res) => {
  try {
    const response = await axios.get(`${CUSTOMER_PROFILE_SERVICE_URL}/api/customers/${req.params.id}`);
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
  console.log(`BankUI Landing server running on port ${port}`);
});

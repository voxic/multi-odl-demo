const express = require('express');
const mysql = require('mysql2/promise');
const bodyParser = require('body-parser');
const cors = require('cors');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3001;

// Middleware
app.use(cors());
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(express.static('public'));

// Database configuration
const dbConfig = {
  host: process.env.MYSQL_HOST || 'localhost',
  port: process.env.MYSQL_PORT || 3306,
  user: process.env.MYSQL_USER || 'odl_user',
  password: process.env.MYSQL_PASSWORD || 'odl_password',
  database: process.env.MYSQL_DATABASE || 'banking'
};

// Create database connection pool
const pool = mysql.createPool({
  ...dbConfig,
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0
});

// Routes
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Get all customers
app.get('/api/customers', async (req, res) => {
  try {
    const [rows] = await pool.execute(`
      SELECT customer_id, first_name, last_name, email, phone, 
             date_of_birth, address_line1, address_line2, city, 
             state, postal_code, country, customer_status,
             created_at, updated_at
      FROM customers 
      ORDER BY customer_id DESC 
      LIMIT 50
    `);
    res.json(rows);
  } catch (error) {
    console.error('Error fetching customers:', error);
    res.status(500).json({ error: 'Failed to fetch customers' });
  }
});

// Get customer by ID
app.get('/api/customers/:id', async (req, res) => {
  try {
    const [rows] = await pool.execute(
      'SELECT * FROM customers WHERE customer_id = ?',
      [req.params.id]
    );
    if (rows.length === 0) {
      return res.status(404).json({ error: 'Customer not found' });
    }
    res.json(rows[0]);
  } catch (error) {
    console.error('Error fetching customer:', error);
    res.status(500).json({ error: 'Failed to fetch customer' });
  }
});

// Update customer
app.put('/api/customers/:id', async (req, res) => {
  try {
    const { first_name, last_name, email, phone, address_line1, 
            address_line2, city, state, postal_code, country, customer_status } = req.body;
    
    const [result] = await pool.execute(`
      UPDATE customers 
      SET first_name = ?, last_name = ?, email = ?, phone = ?,
          address_line1 = ?, address_line2 = ?, city = ?, state = ?,
          postal_code = ?, country = ?, customer_status = ?,
          updated_at = CURRENT_TIMESTAMP
      WHERE customer_id = ?
    `, [first_name, last_name, email, phone, address_line1, 
        address_line2, city, state, postal_code, country, customer_status, req.params.id]);
    
    if (result.affectedRows === 0) {
      return res.status(404).json({ error: 'Customer not found' });
    }
    
    res.json({ message: 'Customer updated successfully' });
  } catch (error) {
    console.error('Error updating customer:', error);
    if (error.code === 'ER_DUP_ENTRY') {
      res.status(400).json({ error: 'Email already exists' });
    } else {
      res.status(500).json({ error: 'Failed to update customer' });
    }
  }
});

// Get accounts for a customer
app.get('/api/customers/:id/accounts', async (req, res) => {
  try {
    const [rows] = await pool.execute(`
      SELECT account_id, account_number, account_type, balance, 
             currency, account_status, interest_rate, credit_limit,
             opened_date, closed_date, created_at, updated_at
      FROM accounts 
      WHERE customer_id = ? 
      ORDER BY account_id DESC
    `, [req.params.id]);
    res.json(rows);
  } catch (error) {
    console.error('Error fetching accounts:', error);
    res.status(500).json({ error: 'Failed to fetch accounts' });
  }
});

// Update account
app.put('/api/accounts/:id', async (req, res) => {
  try {
    const { account_type, balance, account_status, interest_rate, credit_limit } = req.body;
    
    const [result] = await pool.execute(`
      UPDATE accounts 
      SET account_type = ?, balance = ?, account_status = ?, 
          interest_rate = ?, credit_limit = ?, updated_at = CURRENT_TIMESTAMP
      WHERE account_id = ?
    `, [account_type, balance, account_status, interest_rate, credit_limit, req.params.id]);
    
    if (result.affectedRows === 0) {
      return res.status(404).json({ error: 'Account not found' });
    }
    
    res.json({ message: 'Account updated successfully' });
  } catch (error) {
    console.error('Error updating account:', error);
    res.status(500).json({ error: 'Failed to update account' });
  }
});

// Get transactions for an account
app.get('/api/accounts/:id/transactions', async (req, res) => {
  try {
    const [rows] = await pool.execute(`
      SELECT transaction_id, transaction_type, amount, currency, 
             description, reference_number, counterparty_account,
             transaction_date, posted_date, status, created_at, updated_at
      FROM transactions 
      WHERE account_id = ? 
      ORDER BY transaction_date DESC 
      LIMIT 20
    `, [req.params.id]);
    res.json(rows);
  } catch (error) {
    console.error('Error fetching transactions:', error);
    res.status(500).json({ error: 'Failed to fetch transactions' });
  }
});

// Add new transaction
app.post('/api/accounts/:id/transactions', async (req, res) => {
  try {
    const { transaction_type, amount, description, reference_number } = req.body;
    
    const [result] = await pool.execute(`
      INSERT INTO transactions (account_id, transaction_type, amount, currency, 
                              description, reference_number, transaction_date, 
                              posted_date, status)
      VALUES (?, ?, ?, 'USD', ?, ?, NOW(), NOW(), 'COMPLETED')
    `, [req.params.id, transaction_type, amount, description, reference_number]);
    
    res.json({ 
      message: 'Transaction added successfully',
      transaction_id: result.insertId 
    });
  } catch (error) {
    console.error('Error adding transaction:', error);
    res.status(500).json({ error: 'Failed to add transaction' });
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'OK', timestamp: new Date().toISOString() });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Something went wrong!' });
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Legacy Banking UI server running on port ${PORT}`);
  console.log(`Database: ${dbConfig.host}:${dbConfig.port}/${dbConfig.database}`);
});

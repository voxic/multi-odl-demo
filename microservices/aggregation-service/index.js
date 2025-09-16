const { MongoClient } = require('mongodb');
const express = require('express');
const winston = require('winston');
require('dotenv').config();

// Configure logger
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: 'aggregation-service.log' })
  ]
});

// MongoDB connection strings
const CLUSTER1_URI = process.env.CLUSTER1_URI || 'mongodb+srv://odl-reader:password@cluster1.mongodb.net/banking?retryWrites=true&w=majority';
const CLUSTER2_URI = process.env.CLUSTER2_URI || 'mongodb+srv://odl-writer:password@cluster2.mongodb.net/analytics?retryWrites=true&w=majority';

let cluster1Client, cluster2Client;
let isProcessing = false;

// Initialize MongoDB connections
async function initializeConnections() {
  try {
    cluster1Client = new MongoClient(CLUSTER1_URI);
    cluster2Client = new MongoClient(CLUSTER2_URI);
    
    await cluster1Client.connect();
    await cluster2Client.connect();
    
    logger.info('Connected to both MongoDB Atlas clusters');
    
    // Test connections
    await cluster1Client.db('banking').admin().ping();
    await cluster2Client.db('analytics').admin().ping();
    
    logger.info('MongoDB Atlas clusters are healthy');
  } catch (error) {
    logger.error('Failed to connect to MongoDB Atlas clusters:', error);
    process.exit(1);
  }
}

// Aggregate customer data from Cluster 1 to Cluster 2
async function aggregateCustomerData(customerId) {
  try {
    const db1 = cluster1Client.db('banking');
    const db2 = cluster2Client.db('analytics');
    
    // Get customer data
    const customer = await db1.collection('customers').findOne({ customer_id: customerId });
    if (!customer) {
      logger.warn(`Customer ${customerId} not found in Cluster 1`);
      return;
    }
    
    // Get customer accounts
    const accounts = await db1.collection('accounts').find({ customer_id: customerId }).toArray();
    
    // Get recent transactions (last 30 days)
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    
    const transactions = await db1.collection('transactions').find({
      account_id: { $in: accounts.map(acc => acc.account_id) },
      transaction_date: { $gte: thirtyDaysAgo }
    }).toArray();
    
    // Calculate aggregated data
    const totalBalance = accounts.reduce((sum, acc) => sum + (acc.financial_info?.balance || 0), 0);
    const accountTypes = [...new Set(accounts.map(acc => acc.account_details?.account_type))];
    const avgMonthlyTransactions = Math.round(transactions.length / 1); // Simplified for demo
    
    const lastTransactionDate = transactions.length > 0 
      ? new Date(Math.max(...transactions.map(t => new Date(t.transaction_date))))
      : null;
    
    // Create analytics document
    const analyticsDoc = {
      customer_id: customerId,
      profile: {
        name: `${customer.personal_info?.first_name || ''} ${customer.personal_info?.last_name || ''}`.trim(),
        email: customer.personal_info?.email || '',
        location: `${customer.address?.city || ''}, ${customer.address?.state || ''}`.trim(),
        status: customer.status || 'UNKNOWN'
      },
      financial_summary: {
        total_accounts: accounts.length,
        total_balance: totalBalance,
        account_types: accountTypes,
        avg_monthly_transactions: avgMonthlyTransactions,
        last_transaction_date: lastTransactionDate
      },
      risk_profile: {
        credit_score_band: calculateCreditScoreBand(totalBalance, accounts.length),
        default_risk: calculateDefaultRisk(totalBalance, transactions.length),
        transaction_pattern: calculateTransactionPattern(transactions.length)
      },
      computed_at: new Date()
    };
    
    // Upsert to Cluster 2
    await db2.collection('customer_analytics').replaceOne(
      { customer_id: customerId },
      analyticsDoc,
      { upsert: true }
    );
    
    logger.info(`Aggregated data for customer ${customerId}`);
    
  } catch (error) {
    logger.error(`Error aggregating data for customer ${customerId}:`, error);
  }
}

// Helper functions for risk calculation
function calculateCreditScoreBand(balance, accountCount) {
  if (balance > 50000 && accountCount > 2) return 'EXCELLENT';
  if (balance > 25000 && accountCount > 1) return 'GOOD';
  if (balance > 10000) return 'FAIR';
  return 'POOR';
}

function calculateDefaultRisk(balance, transactionCount) {
  if (balance > 0 && transactionCount > 10) return 'LOW';
  if (balance > 0) return 'MEDIUM';
  return 'HIGH';
}

function calculateTransactionPattern(transactionCount) {
  if (transactionCount > 20) return 'REGULAR';
  if (transactionCount > 5) return 'MODERATE';
  return 'LOW';
}

// Process all customers
async function processAllCustomers() {
  if (isProcessing) {
    logger.info('Processing already in progress, skipping...');
    return;
  }
  
  isProcessing = true;
  logger.info('Starting customer aggregation process...');
  
  try {
    const db1 = cluster1Client.db('banking');
    const customers = await db1.collection('customers').find({}).toArray();
    
    logger.info(`Processing ${customers.length} customers...`);
    
    for (const customer of customers) {
      await aggregateCustomerData(customer.customer_id);
      // Small delay to prevent overwhelming the system
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    
    logger.info('Customer aggregation process completed');
  } catch (error) {
    logger.error('Error in customer aggregation process:', error);
  } finally {
    isProcessing = false;
  }
}

// Set up change streams for real-time processing
async function setupChangeStreams() {
  try {
    const db1 = cluster1Client.db('banking');
    
    // Watch for changes in customers collection
    const customersStream = db1.collection('customers').watch();
    customersStream.on('change', async (change) => {
      logger.info('Customer change detected:', change.operationType);
      if (change.operationType === 'insert' || change.operationType === 'update') {
        const customerId = change.fullDocument?.customer_id || change.documentKey?.customer_id;
        if (customerId) {
          await aggregateCustomerData(customerId);
        }
      }
    });
    
    // Watch for changes in accounts collection
    const accountsStream = db1.collection('accounts').watch();
    accountsStream.on('change', async (change) => {
      logger.info('Account change detected:', change.operationType);
      if (change.operationType === 'insert' || change.operationType === 'update') {
        const customerId = change.fullDocument?.customer_id || change.documentKey?.customer_id;
        if (customerId) {
          await aggregateCustomerData(customerId);
        }
      }
    });
    
    logger.info('Change streams setup completed');
  } catch (error) {
    logger.error('Error setting up change streams:', error);
  }
}

// Express app for health checks and manual triggers
const app = express();
app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    timestamp: new Date().toISOString(),
    processing: isProcessing
  });
});

app.post('/aggregate', async (req, res) => {
  const { customerId } = req.body;
  
  if (customerId) {
    await aggregateCustomerData(customerId);
    res.json({ message: `Aggregated data for customer ${customerId}` });
  } else {
    await processAllCustomers();
    res.json({ message: 'Started aggregation for all customers' });
  }
});

app.get('/stats', async (req, res) => {
  try {
    const db1 = cluster1Client.db('banking');
    const db2 = cluster2Client.db('analytics');
    
    const customerCount = await db1.collection('customers').countDocuments();
    const analyticsCount = await db2.collection('customer_analytics').countDocuments();
    
    res.json({
      cluster1_customers: customerCount,
      cluster2_analytics: analyticsCount,
      processing: isProcessing
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Initialize and start the service
async function start() {
  try {
    await initializeConnections();
    
    // Initial aggregation
    await processAllCustomers();
    
    // Setup change streams for real-time processing
    await setupChangeStreams();
    
    // Start Express server
    const port = process.env.PORT || 3000;
    app.listen(port, () => {
      logger.info(`Aggregation service started on port ${port}`);
    });
    
    // Periodic full aggregation (every 5 minutes)
    setInterval(processAllCustomers, 5 * 60 * 1000);
    
  } catch (error) {
    logger.error('Failed to start aggregation service:', error);
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGINT', async () => {
  logger.info('Shutting down aggregation service...');
  if (cluster1Client) await cluster1Client.close();
  if (cluster2Client) await cluster2Client.close();
  process.exit(0);
});

start();

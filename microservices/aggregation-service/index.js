const { MongoClient, Long } = require('mongodb');
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

// Helper function to decode base64 encoded fields
function decodeBase64Field(value) {
  if (typeof value === 'string' && value.length > 0) {
    try {
      // Try to decode as base64
      const buffer = Buffer.from(value, 'base64');
      
      // Try to interpret as binary-encoded number
      if (buffer.length === 1) {
        // 8-bit integer
        return buffer.readUInt8(0);
      } else if (buffer.length === 2) {
        // 16-bit integer
        return buffer.readUInt16BE(0);
      } else if (buffer.length === 3) {
        // 3-byte case - treat as 16-bit integer from first 2 bytes
        return buffer.readUInt16BE(0);
      } else if (buffer.length === 4) {
        // 32-bit integer
        return buffer.readUInt32BE(0);
      } else if (buffer.length === 8) {
        // 64-bit integer
        return Number(buffer.readBigUInt64BE(0));
      } else {
        // Try as text first
        const decoded = buffer.toString('utf-8');
        const num = parseFloat(decoded);
        if (!isNaN(num)) {
          return num;
        }
        return decoded;
      }
    } catch (error) {
      // If decoding fails, return original value
      return value;
    }
  }
  return value;
}

// Helper function to safely get numeric values from CDC data
function safeNumber(value, defaultValue = 0) {
  if (value === null || value === undefined) return defaultValue;
  
  // Handle NumberLong objects
  if (typeof value === 'object' && value.$numberLong) {
    return parseInt(value.$numberLong);
  }
  
  // Handle base64 encoded values
  if (typeof value === 'string') {
    const decoded = decodeBase64Field(value);
    const num = parseFloat(decoded);
    return isNaN(num) ? defaultValue : num;
  }
  
  const num = parseFloat(value);
  return isNaN(num) ? defaultValue : num;
}

// Helper function to safely get string values from CDC data
function safeString(value, defaultValue = '') {
  if (value === null || value === undefined) return defaultValue;
  
  // Handle base64 encoded values
  if (typeof value === 'string') {
    const decoded = decodeBase64Field(value);
    return decoded;
  }
  
  return String(value);
}

// Helper function to safely get date values from CDC data
function safeDate(value) {
  if (value === null || value === undefined) return null;
  
  // Handle NumberLong timestamps
  if (typeof value === 'object' && value.$numberLong) {
    return new Date(parseInt(value.$numberLong));
  }
  
  // Handle string dates
  if (typeof value === 'string') {
    return new Date(value);
  }
  
  return new Date(value);
}

// Extract actual data from CDC event
function extractDataFromCDC(cdcEvent) {
  if (!cdcEvent || !cdcEvent.after) return null;
  return cdcEvent.after;
}

// Helper function to get customer ID from CDC data
function getCustomerIdFromCDC(cdcEvent) {
  if (!cdcEvent || !cdcEvent.after) return null;
  return safeNumber(cdcEvent.after.customer_id);
}

// Helper function to get account ID from CDC data
function getAccountIdFromCDC(cdcEvent) {
  if (!cdcEvent || !cdcEvent.after) return null;
  return safeNumber(cdcEvent.after.account_id);
}

// Aggregate customer data from Cluster 1 to Cluster 2
async function aggregateCustomerData(customerId) {
  try {
    const db1 = cluster1Client.db('banking');
    const db2 = cluster2Client.db('analytics');
    
    // Get customer data from CDC events
    const customerCDC = await db1.collection('customers').findOne({ 
      'after.customer_id': Long.fromString(customerId.toString()) 
    });
    
    if (!customerCDC) {
      logger.warn(`Customer ${customerId} not found in Cluster 1`);
      return;
    }
    
    const customer = extractDataFromCDC(customerCDC);
    if (!customer) {
      logger.warn(`Customer ${customerId} data is invalid`);
      return;
    }
    
    logger.info(`Processing customer ${customerId}: ${safeString(customer.first_name)} ${safeString(customer.last_name)}`);
    
    // Get customer accounts from CDC events
    const accountsCDC = await db1.collection('accounts').find({ 
      'after.customer_id': Long.fromString(customerId.toString()) 
    }).toArray();
    
    const accounts = accountsCDC.map(cdc => extractDataFromCDC(cdc)).filter(Boolean);
    
    // Get customer agreements from CDC events
    const agreementsCDC = await db1.collection('agreements').find({ 
      'after.customer_id': Long.fromString(customerId.toString()) 
    }).toArray();
    
    const agreements = agreementsCDC.map(cdc => extractDataFromCDC(cdc)).filter(Boolean);
    
    // Get recent transactions (last 30 days) from CDC events
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    
    const accountIds = accounts.map(acc => Long.fromString(acc.account_id.toString()));
    const transactionsCDC = await db1.collection('transactions').find({
      'after.account_id': { $in: accountIds },
      'after.transaction_date': { 
        $gte: Long.fromNumber(thirtyDaysAgo.getTime())
      }
    }).toArray();
    
    const transactions = transactionsCDC.map(cdc => extractDataFromCDC(cdc)).filter(Boolean);
    
    // Calculate aggregated data
    const totalBalance = accounts.reduce((sum, acc) => sum + safeNumber(acc.balance), 0);
    const accountTypes = [...new Set(accounts.map(acc => acc.account_type).filter(Boolean))];
    const avgMonthlyTransactions = Math.round(transactions.length / 1); // Simplified for demo
    
    const lastTransactionDate = transactions.length > 0 
      ? new Date(Math.max(...transactions.map(t => safeNumber(t.transaction_date))))
      : null;
    
    // Calculate agreement metrics
    const totalAgreements = agreements.length;
    const activeAgreements = agreements.filter(agr => agr.status === 'ACTIVE').length;
    const totalPrincipalAmount = agreements.reduce((sum, agr) => sum + safeNumber(agr.principal_amount), 0);
    const totalCurrentBalance = agreements.reduce((sum, agr) => sum + safeNumber(agr.current_balance), 0);
    
    // Create analytics document
    const analyticsDoc = {
      customer_id: customerId,
      profile: {
        name: `${safeString(customer.first_name)} ${safeString(customer.last_name)}`.trim(),
        email: safeString(customer.email),
        location: `${safeString(customer.city)}, ${safeString(customer.state)}`.trim(),
        status: safeString(customer.customer_status, 'UNKNOWN'),
        phone: safeString(customer.phone),
        address: `${safeString(customer.address_line1)} ${safeString(customer.address_line2 || '')}`.trim(),
        postal_code: safeString(customer.postal_code),
        country: safeString(customer.country),
        date_of_birth: safeDate(customer.date_of_birth)
      },
      financial_summary: {
        total_accounts: accounts.length,
        total_balance: totalBalance,
        account_types: accountTypes,
        avg_monthly_transactions: avgMonthlyTransactions,
        last_transaction_date: lastTransactionDate,
        total_agreements: totalAgreements,
        active_agreements: activeAgreements,
        total_principal_amount: totalPrincipalAmount,
        total_current_balance: totalCurrentBalance
      },
      risk_profile: {
        credit_score_band: calculateCreditScoreBand(totalBalance, accounts.length, totalAgreements),
        default_risk: calculateDefaultRisk(totalBalance, transactions.length, totalCurrentBalance),
        transaction_pattern: calculateTransactionPattern(transactions.length),
        agreement_risk: calculateAgreementRisk(agreements.length, totalCurrentBalance, totalPrincipalAmount)
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
function calculateCreditScoreBand(balance, accountCount, agreementCount) {
  if (balance > 50000 && accountCount > 2 && agreementCount > 0) return 'EXCELLENT';
  if (balance > 25000 && accountCount > 1) return 'GOOD';
  if (balance > 10000) return 'FAIR';
  return 'POOR';
}

function calculateDefaultRisk(balance, transactionCount, currentBalance) {
  if (balance > 0 && transactionCount > 10 && currentBalance < balance * 0.5) return 'LOW';
  if (balance > 0 && currentBalance < balance) return 'MEDIUM';
  return 'HIGH';
}

function calculateTransactionPattern(transactionCount) {
  if (transactionCount > 20) return 'REGULAR';
  if (transactionCount > 5) return 'MODERATE';
  return 'LOW';
}

function calculateAgreementRisk(agreementCount, currentBalance, principalAmount) {
  if (agreementCount === 0) return 'NONE';
  if (currentBalance > principalAmount * 0.8) return 'HIGH';
  if (currentBalance > principalAmount * 0.5) return 'MEDIUM';
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
    
    // Get all unique customer IDs from CDC events
    const customersCDC = await db1.collection('customers').find({}).toArray();
    const customerIds = [...new Set(customersCDC.map(cdc => {
      const customer = extractDataFromCDC(cdc);
      return customer ? safeNumber(customer.customer_id) : null;
    }).filter(Boolean))];
    
    logger.info(`Processing ${customerIds.length} customers...`);
    
    for (const customerId of customerIds) {
      await aggregateCustomerData(customerId);
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

// Set up change streams for real-time processing of CDC events
async function setupChangeStreams() {
  try {
    const db1 = cluster1Client.db('banking');
    
    // Watch for changes in customers collection
    const customersStream = db1.collection('customers').watch();
    customersStream.on('change', async (change) => {
      logger.info('Customer change detected:', change.operationType);
      if (change.operationType === 'insert' || change.operationType === 'update') {
        const customer = extractDataFromCDC(change.fullDocument);
        if (customer && customer.customer_id) {
          const customerId = safeNumber(customer.customer_id);
          logger.info(`Triggering aggregation for customer ${customerId} due to customer change`);
          await aggregateCustomerData(customerId);
        }
      }
    });
    
    // Watch for changes in accounts collection
    const accountsStream = db1.collection('accounts').watch();
    accountsStream.on('change', async (change) => {
      logger.info('Account change detected:', change.operationType);
      if (change.operationType === 'insert' || change.operationType === 'update') {
        const account = extractDataFromCDC(change.fullDocument);
        if (account && account.customer_id) {
          const customerId = safeNumber(account.customer_id);
          logger.info(`Triggering aggregation for customer ${customerId} due to account change`);
          await aggregateCustomerData(customerId);
        }
      }
    });
    
    // Watch for changes in agreements collection
    const agreementsStream = db1.collection('agreements').watch();
    agreementsStream.on('change', async (change) => {
      logger.info('Agreement change detected:', change.operationType);
      if (change.operationType === 'insert' || change.operationType === 'update') {
        const agreement = extractDataFromCDC(change.fullDocument);
        if (agreement && agreement.customer_id) {
          const customerId = safeNumber(agreement.customer_id);
          logger.info(`Triggering aggregation for customer ${customerId} due to agreement change`);
          await aggregateCustomerData(customerId);
        }
      }
    });
    
    // Watch for changes in transactions collection
    const transactionsStream = db1.collection('transactions').watch();
    transactionsStream.on('change', async (change) => {
      logger.info('Transaction change detected:', change.operationType);
      if (change.operationType === 'insert' || change.operationType === 'update') {
        const transaction = extractDataFromCDC(change.fullDocument);
        if (transaction && transaction.account_id) {
          // Find the customer for this account
          const accountCDC = await db1.collection('accounts').findOne({ 
            'after.account_id': Long.fromString(transaction.account_id.toString()) 
          });
          if (accountCDC) {
            const account = extractDataFromCDC(accountCDC);
            if (account && account.customer_id) {
              const customerId = safeNumber(account.customer_id);
              logger.info(`Triggering aggregation for customer ${customerId} due to transaction change`);
              await aggregateCustomerData(customerId);
            }
          }
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
    
    // Count unique customers from CDC events
    const customersCDC = await db1.collection('customers').find({}).toArray();
    const uniqueCustomers = new Set(customersCDC.map(cdc => {
      const customer = extractDataFromCDC(cdc);
      return customer ? safeNumber(customer.customer_id) : null;
    }).filter(Boolean));
    
    const analyticsCount = await db2.collection('customer_analytics').countDocuments();
    
    res.json({
      cluster1_customers: uniqueCustomers.size,
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
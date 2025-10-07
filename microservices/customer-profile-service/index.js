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
    new winston.transports.File({ filename: 'customer-profile-service.log' })
  ]
});

// MongoDB connection strings
const CLUSTER1_URI = process.env.CLUSTER1_URI || 'mongodb+srv://odl-reader:password@cluster1.mongodb.net/banking?w=majority&retryReads=true';
const CLUSTER2_URI = process.env.CLUSTER2_URI || 'mongodb+srv://odl-writer:password@cluster2.mongodb.net/analytics?w=majority&retryReads=true';

let cluster1Client, cluster2Client;
let isProcessing = false;

async function initializeConnections() {
  try {
    cluster1Client = new MongoClient(CLUSTER1_URI);
    cluster2Client = new MongoClient(CLUSTER2_URI);

    await cluster1Client.connect();
    await cluster2Client.connect();

    logger.info('Connected to both MongoDB Atlas clusters (profile service)');

    await cluster1Client.db('banking').admin().ping();
    await cluster2Client.db('analytics').admin().ping();
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

function safeNumber(value, defaultValue = 0) {
  if (value === null || value === undefined) return defaultValue;
  if (typeof value === 'object' && value.$numberLong) {
    return parseInt(value.$numberLong);
  }
  const num = parseFloat(value);
  return isNaN(num) ? defaultValue : num;
}

// Helper function to safely get base64-encoded numeric values from CDC data
function safeBase64Number(value, defaultValue = 0) {
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

// Helper function to safely get currency amounts (stored in cents, convert to dollars)
function safeCurrencyAmount(value, defaultValue = 0) {
  if (value === null || value === undefined) return defaultValue;
  
  // Handle NumberLong objects
  if (typeof value === 'object' && value.$numberLong) {
    return parseInt(value.$numberLong) / 100; // Convert cents to dollars
  }
  
  // Handle base64 encoded values (stored as cents)
  if (typeof value === 'string') {
    const decoded = decodeBase64Field(value);
    const num = parseFloat(decoded);
    return isNaN(num) ? defaultValue : num / 100; // Convert cents to dollars
  }
  
  const num = parseFloat(value);
  return isNaN(num) ? defaultValue : num / 100; // Convert cents to dollars
}

function safeString(value, defaultValue = '') {
  if (value === null || value === undefined) return defaultValue;
  if (typeof value === 'string') return value;
  return String(value);
}

function safeDate(value) {
  if (value === null || value === undefined) return null;
  if (typeof value === 'object' && value.$numberLong) {
    return new Date(parseInt(value.$numberLong));
  }
  if (typeof value === 'string') return new Date(value);
  return new Date(value);
}

function extractDataFromCDC(cdcEvent) {
  if (!cdcEvent) return null;
  
  // Handle actual CDC events from Debezium (with op, before, after structure)
  if (cdcEvent.op && cdcEvent.after) {
    return cdcEvent.after;
  }
  
  // Handle legacy CDC events (direct after structure)
  if (cdcEvent.after) {
    return cdcEvent.after;
  }
  
  // Handle regular MongoDB documents (no CDC structure)
  // Return the document as-is if it doesn't have CDC structure
  return cdcEvent;
}

async function buildCustomerProfile(customerId) {
  try {
    const db1 = cluster1Client.db('banking');
    const db2 = cluster2Client.db('analytics');

    // Get customer data - handle both CDC events and regular documents
    // Sort by timestamp to get the latest CDC event
    const customerCDC = await db1.collection('customers').findOne({
      $or: [
        // CDC event format
        { 'after.customer_id': Long.fromString(customerId.toString()) },
        { 'after.customer_id': customerId },
        // Regular document format
        { 'customer_id': Long.fromString(customerId.toString()) },
        { 'customer_id': customerId }
      ]
    }, { 
      sort: { 
        'ts_ms': -1,  // Sort by timestamp descending to get latest
        '_id': -1     // Secondary sort by _id for consistency
      } 
    });
    if (!customerCDC) {
      logger.warn(`Customer ${customerId} not found`);
      return;
    }
    const customer = extractDataFromCDC(customerCDC);
    if (!customer) {
      logger.warn(`Customer ${customerId} data is invalid after extraction`);
      return;
    }
    
    logger.info(`Building profile for customer ${customerId}: ${safeString(customer.first_name)} ${safeString(customer.last_name)}`);

    // Get customer accounts - handle both CDC events and regular documents
    const accountsCDC = await db1.collection('accounts').find({
      $or: [
        // CDC event format
        { 'after.customer_id': Long.fromString(customerId.toString()) },
        { 'after.customer_id': customerId },
        // Regular document format
        { 'customer_id': Long.fromString(customerId.toString()) },
        { 'customer_id': customerId }
      ]
    }, {
      sort: { 
        'ts_ms': -1,  // Sort by timestamp descending to get latest
        '_id': -1     // Secondary sort by _id for consistency
      }
    }).toArray();
    
    // Extract account data and deduplicate by account_id, keeping only the latest version
    const accountsMap = new Map();
    accountsCDC.forEach(cdc => {
      const account = extractDataFromCDC(cdc);
      if (account && account.account_id) {
        const accountId = safeBase64Number(account.account_id);
        // Only keep the latest version of each account (since we sorted by ts_ms desc)
        if (!accountsMap.has(accountId)) {
          // Debug logging for account data
          logger.info(`Account ${accountId} raw data:`, JSON.stringify(account, null, 2));
          logger.info(`Account ${accountId} balance raw:`, account.balance);
          logger.info(`Account ${accountId} balance decoded:`, safeCurrencyAmount(account.balance));
          accountsMap.set(accountId, account);
        }
      }
    });
    const accounts = Array.from(accountsMap.values());

    // Fetch 10 most recent transactions per account
    const accountOverviews = [];
    for (const account of accounts) {
      const accountId = safeBase64Number(account.account_id);
      const txCDC = await db1.collection('transactions')
        .find({ 
          $or: [
            // CDC event format
            { 'after.account_id': Long.fromString(accountId.toString()) },
            { 'after.account_id': accountId },
            // Regular document format
            { 'account_id': Long.fromString(accountId.toString()) },
            { 'account_id': accountId }
          ]
        })
        .sort({ 
          'ts_ms': -1,  // Sort by timestamp descending to get latest
          '_id': -1     // Secondary sort by _id for consistency
        })
        .limit(10)
        .toArray();
      // Extract transaction data and deduplicate by transaction_id, keeping only the latest version
      const transactionsMap = new Map();
      txCDC.forEach(cdc => {
        const transaction = extractDataFromCDC(cdc);
        if (transaction && transaction.transaction_id) {
          const transactionId = safeBase64Number(transaction.transaction_id);
          // Only keep the latest version of each transaction (since we sorted by ts_ms desc)
          if (!transactionsMap.has(transactionId)) {
            // Debug logging for transaction amounts
            logger.info(`Transaction ${transactionId} amount raw:`, transaction.amount);
            logger.info(`Transaction ${transactionId} amount decoded:`, safeCurrencyAmount(transaction.amount));
            transactionsMap.set(transactionId, {
              transaction_id: transactionId,
              transaction_date: safeDate(transaction.transaction_date),
              amount: safeCurrencyAmount(transaction.amount),
              type: safeString(transaction.transaction_type),
              description: safeString(transaction.description)
            });
          }
        }
      });
      const transactions = Array.from(transactionsMap.values());

      accountOverviews.push({
        account_id: safeBase64Number(account.account_id),
        account_type: safeString(account.account_type),
        balance: safeCurrencyAmount(account.balance),
        currency: safeString(account.currency, 'USD'),
        transactions
      });
    }

    const profileDoc = {
      customer_id: safeBase64Number(customer.customer_id),
      profile: {
        name: `${safeString(customer.first_name)} ${safeString(customer.last_name)}`.trim(),
        email: safeString(customer.email),
        phone: safeString(customer.phone),
        address: `${safeString(customer.address_line1)} ${safeString(customer.address_line2 || '')}`.trim(),
        location: `${safeString(customer.city)}, ${safeString(customer.state)}`.trim(),
        postal_code: safeString(customer.postal_code),
        country: safeString(customer.country),
        status: safeString(customer.customer_status, 'UNKNOWN'),
        date_of_birth: safeDate(customer.date_of_birth)
      },
      accounts: accountOverviews,
      updated_at: new Date()
    };

    const result = await db2.collection('customer_profile').replaceOne(
      { customer_id: profileDoc.customer_id },
      profileDoc,
      { upsert: true }
    );

    logger.info(`Upserted customer_profile for ${customerId}`, {
      matchedCount: result.matchedCount,
      modifiedCount: result.modifiedCount,
      upsertedId: result.upsertedId
    });
  } catch (error) {
    logger.error(`Error building customer profile for ${customerId}:`, error);
  }
}

async function processAllCustomers() {
  if (isProcessing) return;
  isProcessing = true;
  try {
    const db1 = cluster1Client.db('banking');
    const customersCDC = await db1.collection('customers').find({}).toArray();
    const customerIds = [...new Set(customersCDC.map(cdc => {
      const c = extractDataFromCDC(cdc);
      return c ? safeBase64Number(c.customer_id) : null;
    }).filter(Boolean))];
    
    logger.info(`Found ${customerIds.length} unique customers to process`);

    for (const customerId of customerIds) {
      await buildCustomerProfile(customerId);
      await new Promise(r => setTimeout(r, 50));
    }
  } catch (error) {
    logger.error('Error processing all customers:', error);
  } finally {
    isProcessing = false;
  }
}

async function setupChangeStreams() {
  try {
    const db1 = cluster1Client.db('banking');

    const customersStream = db1.collection('customers').watch([], { fullDocument: 'updateLookup' });
    customersStream.on('change', async (change) => {
      logger.info('=== CUSTOMER CHANGE STREAM EVENT (PROFILE SERVICE) ===');
      logger.info('Operation Type:', change.operationType);
      logger.info('Full Change Document:', JSON.stringify(change, null, 2));
      
      if (change.operationType === 'insert' || change.operationType === 'update') {
        logger.info('Processing insert/update event...');
        
        // Log the full document structure
        logger.info('Full Document:', JSON.stringify(change.fullDocument, null, 2));
        
        // Try different extraction methods
        let customer = null;
        
        // Method 1: Direct extraction
        if (change.fullDocument && change.fullDocument.after) {
          customer = change.fullDocument.after;
          logger.info('Extracted via .after:', JSON.stringify(customer, null, 2));
        }
        
        // Method 2: Use existing extractDataFromCDC function
        if (!customer) {
          customer = extractDataFromCDC(change.fullDocument);
          logger.info('Extracted via extractDataFromCDC:', JSON.stringify(customer, null, 2));
        }
        
        // Method 3: Direct fullDocument if it's not CDC format
        if (!customer && change.fullDocument) {
          customer = change.fullDocument;
          logger.info('Using fullDocument directly:', JSON.stringify(customer, null, 2));
        }
        
        if (customer && customer.customer_id) {
          const customerId = safeBase64Number(customer.customer_id);
          logger.info(`✅ Valid customer data found! Customer ID: ${customerId}`);
          logger.info(`Triggering profile rebuild for customer ${customerId} due to customer change`);
          await buildCustomerProfile(customerId);
        } else {
          logger.warn('❌ No valid customer data found in change event');
          logger.warn('Customer object:', JSON.stringify(customer, null, 2));
        }
      } else {
        logger.info(`Skipping ${change.operationType} operation`);
      }
      logger.info('=== END CUSTOMER CHANGE STREAM EVENT (PROFILE SERVICE) ===');
    });

    const accountsStream = db1.collection('accounts').watch([], { fullDocument: 'updateLookup' });
    accountsStream.on('change', async (change) => {
      logger.info('=== ACCOUNT CHANGE STREAM EVENT (PROFILE SERVICE) ===');
      logger.info('Operation Type:', change.operationType);
      logger.info('Full Change Document:', JSON.stringify(change, null, 2));
      
      if (change.operationType === 'insert' || change.operationType === 'update') {
        logger.info('Processing insert/update event...');
        
        // Log the full document structure
        logger.info('Full Document:', JSON.stringify(change.fullDocument, null, 2));
        
        // Try different extraction methods
        let account = null;
        
        // Method 1: Direct extraction from fullDocument
        if (change.fullDocument && change.fullDocument.after) {
          account = change.fullDocument.after;
          logger.info('Extracted via .after:', JSON.stringify(account, null, 2));
        }
        
        // Method 2: Use existing extractDataFromCDC function
        if (!account) {
          account = extractDataFromCDC(change.fullDocument);
          logger.info('Extracted via extractDataFromCDC:', JSON.stringify(account, null, 2));
        }
        
        // Method 3: Direct fullDocument if it's not CDC format
        if (!account && change.fullDocument) {
          account = change.fullDocument;
          logger.info('Using fullDocument directly:', JSON.stringify(account, null, 2));
        }
        
        if (account && account.customer_id) {
          const customerId = safeBase64Number(account.customer_id);
          logger.info(`✅ Valid account data found! Customer ID: ${customerId}`);
          logger.info(`Triggering profile rebuild for customer ${customerId} due to account change`);
          await buildCustomerProfile(customerId);
        } else {
          logger.warn('❌ No valid account data found in change event');
          logger.warn('Account object:', JSON.stringify(account, null, 2));
        }
      } else {
        logger.info(`Skipping ${change.operationType} operation`);
      }
      logger.info('=== END ACCOUNT CHANGE STREAM EVENT (PROFILE SERVICE) ===');
    });

    const transactionsStream = db1.collection('transactions').watch([], { fullDocument: 'updateLookup' });
    transactionsStream.on('change', async (change) => {
      logger.info('=== TRANSACTION CHANGE STREAM EVENT (PROFILE SERVICE) ===');
      logger.info('Operation Type:', change.operationType);
      logger.info('Full Change Document:', JSON.stringify(change, null, 2));
      
      if (change.operationType === 'insert' || change.operationType === 'update') {
        logger.info('Processing insert/update event...');
        
        // Log the full document structure
        logger.info('Full Document:', JSON.stringify(change.fullDocument, null, 2));
        
        // Try different extraction methods
        let transaction = null;
        
        // Method 1: Direct extraction from fullDocument
        if (change.fullDocument && change.fullDocument.after) {
          transaction = change.fullDocument.after;
          logger.info('Extracted via .after:', JSON.stringify(transaction, null, 2));
        }
        
        // Method 2: Use existing extractDataFromCDC function
        if (!transaction) {
          transaction = extractDataFromCDC(change.fullDocument);
          logger.info('Extracted via extractDataFromCDC:', JSON.stringify(transaction, null, 2));
        }
        
        // Method 3: Direct fullDocument if it's not CDC format
        if (!transaction && change.fullDocument) {
          transaction = change.fullDocument;
          logger.info('Using fullDocument directly:', JSON.stringify(transaction, null, 2));
        }
        
        if (transaction && transaction.account_id) {
          const accountId = safeBase64Number(transaction.account_id);
          logger.info(`✅ Valid transaction data found! Account ID: ${accountId}`);
          
          // Find the account to get the customer_id - handle both CDC events and regular documents
          const account = await db1.collection('accounts').findOne({
            $or: [
              // CDC event format
              { 'after.account_id': Long.fromString(accountId.toString()) },
              { 'after.account_id': accountId },
              // Regular document format
              { 'account_id': Long.fromString(accountId.toString()) },
              { 'account_id': accountId }
            ]
          }, { 
            sort: { 
              'ts_ms': -1,  // Sort by timestamp descending to get latest
              '_id': -1     // Secondary sort by _id for consistency
            } 
          });
          
          if (account) {
            const accountData = extractDataFromCDC(account);
            if (accountData && accountData.customer_id) {
              const customerId = safeBase64Number(accountData.customer_id);
              logger.info(`✅ Found account ${accountId} for customer ${customerId}`);
              logger.info(`Triggering profile rebuild for customer ${customerId} due to transaction change`);
              await buildCustomerProfile(customerId);
            } else {
              logger.warn(`❌ Could not extract customer_id from account ${accountId}`);
              logger.warn('Account data:', JSON.stringify(accountData, null, 2));
            }
          } else {
            logger.warn(`❌ Could not find account ${accountId} for transaction`);
          }
        } else {
          logger.warn('❌ No valid transaction data found in change event');
          logger.warn('Transaction object:', JSON.stringify(transaction, null, 2));
        }
      } else {
        logger.info(`Skipping ${change.operationType} operation`);
      }
      logger.info('=== END TRANSACTION CHANGE STREAM EVENT (PROFILE SERVICE) ===');
    });
  } catch (error) {
    logger.error('Error setting up change streams:', error);
  }
}

const app = express();
app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', processing: isProcessing, timestamp: new Date().toISOString() });
});

app.post('/profile', async (req, res) => {
  const { customerId } = req.body;
  if (customerId) {
    await buildCustomerProfile(customerId);
    res.json({ message: `Rebuilt profile for ${customerId}` });
  } else {
    await processAllCustomers();
    res.json({ message: 'Started rebuilding profiles for all customers' });
  }
});

app.get('/customers/:id', async (req, res) => {
  try {
    const db2 = cluster2Client.db('analytics');
    const customerId = parseInt(req.params.id);
    const doc = await db2.collection('customer_profile').findOne({ customer_id: customerId });
    if (!doc) return res.status(404).json({ error: 'Profile not found' });
    res.json(doc);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// API endpoints with /api prefix for bankui-landing compatibility
app.get('/api/health', (req, res) => {
  res.json({ status: 'healthy', processing: isProcessing, timestamp: new Date().toISOString() });
});

app.get('/api/customers/random', async (req, res) => {
  try {
    const db2 = cluster2Client.db('analytics');
    
    // Get a random customer profile from the analytics database
    const randomProfile = await db2.collection('customer_profile').aggregate([
      { $sample: { size: 1 } }
    ]).toArray();
    
    if (randomProfile.length === 0) {
      return res.status(404).json({ error: 'No customer profiles found' });
    }
    
    res.json(randomProfile[0]);
  } catch (error) {
    logger.error('Error fetching random customer:', error);
    res.status(500).json({ error: 'Failed to fetch random customer' });
  }
});

app.get('/api/customers/:id', async (req, res) => {
  try {
    const db2 = cluster2Client.db('analytics');
    const customerId = parseInt(req.params.id);
    const doc = await db2.collection('customer_profile').findOne({ customer_id: customerId });
    if (!doc) return res.status(404).json({ error: 'Profile not found' });
    res.json(doc);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

async function start() {
  try {
    await initializeConnections();
    await processAllCustomers();
    await setupChangeStreams();

    const port = process.env.PORT || 3001;
    app.listen(port, () => logger.info(`Customer profile service started on ${port}`));

    setInterval(processAllCustomers, 10 * 60 * 1000);
  } catch (error) {
    logger.error('Failed to start customer profile service:', error);
    process.exit(1);
  }
}

process.on('SIGINT', async () => {
  logger.info('Shutting down customer profile service...');
  if (cluster1Client) await cluster1Client.close();
  if (cluster2Client) await cluster2Client.close();
  process.exit(0);
});

start();



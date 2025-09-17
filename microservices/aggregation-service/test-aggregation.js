const { MongoClient } = require('mongodb');
require('dotenv').config();

// Test script to verify the aggregation service works with Debezium CDC data
async function testAggregation() {
  const CLUSTER1_URI = process.env.CLUSTER1_URI || 'mongodb+srv://odl-reader:password@cluster1.mongodb.net/banking?retryWrites=true&w=majority';
  const CLUSTER2_URI = process.env.CLUSTER2_URI || 'mongodb+srv://odl-writer:password@cluster2.mongodb.net/analytics?retryWrites=true&w=majority';
  
  let cluster1Client, cluster2Client;
  
  try {
    // Connect to both clusters
    cluster1Client = new MongoClient(CLUSTER1_URI);
    cluster2Client = new MongoClient(CLUSTER2_URI);
    
    await cluster1Client.connect();
    await cluster2Client.connect();
    
    console.log('Connected to both MongoDB Atlas clusters');
    
    const db1 = cluster1Client.db('banking');
    const db2 = cluster2Client.db('analytics');
    
    // Test data extraction from CDC events
    console.log('\n=== Testing CDC Data Extraction ===');
    
    // Test customers collection
    const customersCDC = await db1.collection('customers').find({}).limit(1).toArray();
    if (customersCDC.length > 0) {
      console.log('Sample customer CDC event:', JSON.stringify(customersCDC[0], null, 2));
      
      const customer = customersCDC[0].after;
      if (customer) {
        console.log('Extracted customer data:', {
          customer_id: customer.customer_id,
          first_name: customer.first_name,
          last_name: customer.last_name,
          email: customer.email
        });
      }
    }
    
    // Test accounts collection
    const accountsCDC = await db1.collection('accounts').find({}).limit(1).toArray();
    if (accountsCDC.length > 0) {
      console.log('\nSample account CDC event:', JSON.stringify(accountsCDC[0], null, 2));
      
      const account = accountsCDC[0].after;
      if (account) {
        console.log('Extracted account data:', {
          account_id: account.account_id,
          customer_id: account.customer_id,
          account_type: account.account_type,
          balance: account.balance
        });
      }
    }
    
    // Test agreements collection
    const agreementsCDC = await db1.collection('agreements').find({}).limit(1).toArray();
    if (agreementsCDC.length > 0) {
      console.log('\nSample agreement CDC event:', JSON.stringify(agreementsCDC[0], null, 2));
      
      const agreement = agreementsCDC[0].after;
      if (agreement) {
        console.log('Extracted agreement data:', {
          agreement_id: agreement.agreement_id,
          customer_id: agreement.customer_id,
          agreement_type: agreement.agreement_type,
          principal_amount: agreement.principal_amount
        });
      }
    }
    
    // Test transactions collection
    const transactionsCDC = await db1.collection('transactions').find({}).limit(1).toArray();
    if (transactionsCDC.length > 0) {
      console.log('\nSample transaction CDC event:', JSON.stringify(transactionsCDC[0], null, 2));
      
      const transaction = transactionsCDC[0].after;
      if (transaction) {
        console.log('Extracted transaction data:', {
          transaction_id: transaction.transaction_id,
          account_id: transaction.account_id,
          amount: transaction.amount,
          transaction_type: transaction.transaction_type
        });
      }
    }
    
    // Test analytics collection
    const analyticsCount = await db2.collection('customer_analytics').countDocuments();
    console.log(`\nAnalytics collection has ${analyticsCount} documents`);
    
    if (analyticsCount > 0) {
      const sampleAnalytics = await db2.collection('customer_analytics').findOne({});
      console.log('Sample analytics document:', JSON.stringify(sampleAnalytics, null, 2));
    }
    
    console.log('\n=== Test completed successfully ===');
    
  } catch (error) {
    console.error('Test failed:', error);
  } finally {
    if (cluster1Client) await cluster1Client.close();
    if (cluster2Client) await cluster2Client.close();
  }
}

// Run the test
testAggregation();

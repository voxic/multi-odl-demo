const mysql = require('mysql2/promise');
const fs = require('fs');

// Database configuration
const dbConfig = {
  host: process.env.MYSQL_HOST || 'localhost',
  port: process.env.MYSQL_PORT || 3306,
  user: process.env.MYSQL_USER || 'odl_user',
  password: process.env.MYSQL_PASSWORD || 'odl_password',
  database: process.env.MYSQL_DATABASE || 'banking'
};

// Sample data configuration
const config = {
  customers: 100,
  accountsPerCustomer: { min: 1, max: 3 },
  transactionsPerAccount: 10,
  agreementsPercentage: 30,
  dataTimeline: 30 // days
};

// Table creation SQL
const createTablesSQL = `
-- Create customers table
CREATE TABLE IF NOT EXISTS customers (
    customer_id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(20),
    date_of_birth DATE,
    address_line1 VARCHAR(100),
    address_line2 VARCHAR(100),
    city VARCHAR(50),
    state VARCHAR(10),
    postal_code VARCHAR(10),
    country VARCHAR(50),
    customer_status ENUM('ACTIVE', 'INACTIVE', 'SUSPENDED') DEFAULT 'ACTIVE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Create accounts table
CREATE TABLE IF NOT EXISTS accounts (
    account_id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT NOT NULL,
    account_number VARCHAR(50) UNIQUE NOT NULL,
    account_type ENUM('CHECKING', 'SAVINGS', 'CREDIT', 'LOAN') NOT NULL,
    balance DECIMAL(15,2) DEFAULT 0.00,
    currency VARCHAR(3) DEFAULT 'USD',
    account_status ENUM('ACTIVE', 'FROZEN', 'CLOSED') DEFAULT 'ACTIVE',
    interest_rate DECIMAL(5,4) DEFAULT 0.0000,
    credit_limit DECIMAL(15,2),
    opened_date DATE,
    closed_date DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE
);

-- Create transactions table
CREATE TABLE IF NOT EXISTS transactions (
    transaction_id INT AUTO_INCREMENT PRIMARY KEY,
    account_id INT NOT NULL,
    transaction_type ENUM('DEPOSIT', 'WITHDRAWAL', 'TRANSFER_IN', 'TRANSFER_OUT', 'PAYMENT', 'FEE') NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    description TEXT,
    reference_number VARCHAR(50),
    counterparty_account VARCHAR(50),
    transaction_date DATETIME,
    posted_date DATETIME,
    status ENUM('PENDING', 'COMPLETED', 'FAILED', 'CANCELLED') DEFAULT 'PENDING',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
);

-- Create agreements table
CREATE TABLE IF NOT EXISTS agreements (
    agreement_id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT NOT NULL,
    account_id INT NOT NULL,
    agreement_type ENUM('LOAN', 'CREDIT_CARD', 'OVERDRAFT', 'INVESTMENT') NOT NULL,
    agreement_number VARCHAR(50) UNIQUE NOT NULL,
    principal_amount DECIMAL(15,2) NOT NULL,
    current_balance DECIMAL(15,2) DEFAULT 0.00,
    interest_rate DECIMAL(5,4) NOT NULL,
    term_months INT,
    payment_amount DECIMAL(15,2),
    payment_frequency ENUM('MONTHLY', 'QUARTERLY', 'ANNUALLY'),
    start_date DATE,
    end_date DATE,
    status ENUM('ACTIVE', 'COMPLETED', 'DEFAULTED', 'CANCELLED') DEFAULT 'ACTIVE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE,
    FOREIGN KEY (account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_customers_email ON customers(email);
CREATE INDEX IF NOT EXISTS idx_customers_status ON customers(customer_status);
CREATE INDEX IF NOT EXISTS idx_accounts_customer_id ON accounts(customer_id);
CREATE INDEX IF NOT EXISTS idx_accounts_type ON accounts(account_type);
CREATE INDEX IF NOT EXISTS idx_accounts_status ON accounts(account_status);
CREATE INDEX IF NOT EXISTS idx_transactions_account_id ON transactions(account_id);
CREATE INDEX IF NOT EXISTS idx_transactions_type ON transactions(transaction_type);
CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions(transaction_date);
CREATE INDEX IF NOT EXISTS idx_agreements_customer_id ON agreements(customer_id);
CREATE INDEX IF NOT EXISTS idx_agreements_account_id ON agreements(account_id);
CREATE INDEX IF NOT EXISTS idx_agreements_type ON agreements(agreement_type);
`;

// Sample data generators
const firstNames = ['John', 'Jane', 'Michael', 'Sarah', 'David', 'Emily', 'Robert', 'Jessica', 'William', 'Ashley'];
const lastNames = ['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis', 'Rodriguez', 'Martinez'];
const cities = ['New York', 'Los Angeles', 'Chicago', 'Houston', 'Phoenix', 'Philadelphia', 'San Antonio', 'San Diego', 'Dallas', 'San Jose'];
const states = ['NY', 'CA', 'IL', 'TX', 'AZ', 'PA', 'TX', 'CA', 'TX', 'CA'];

function randomChoice(array) {
  return array[Math.floor(Math.random() * array.length)];
}

function randomBetween(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function randomDate(daysAgo) {
  const date = new Date();
  date.setDate(date.getDate() - Math.floor(Math.random() * daysAgo));
  return date;
}

function generateCustomer() {
  const firstName = randomChoice(firstNames);
  const lastName = randomChoice(lastNames);
  const email = `${firstName.toLowerCase()}.${lastName.toLowerCase()}@email.com`;
  
  return {
    first_name: firstName,
    last_name: lastName,
    email: email,
    phone: `+1-555-${String(randomBetween(100, 999)).padStart(3, '0')}-${String(randomBetween(1000, 9999))}`,
    date_of_birth: randomDate(365 * 50), // Random date within last 50 years
    address_line1: `${randomBetween(1, 9999)} ${randomChoice(['Main', 'Oak', 'Pine', 'Cedar', 'Elm'])} St`,
    address_line2: Math.random() > 0.7 ? `Apt ${randomBetween(1, 20)}${randomChoice(['A', 'B', 'C'])}` : null,
    city: randomChoice(cities),
    state: randomChoice(states),
    postal_code: String(randomBetween(10000, 99999)),
    country: 'USA',
    customer_status: randomChoice(['ACTIVE', 'ACTIVE', 'ACTIVE', 'INACTIVE']), // 75% active
    created_at: randomDate(config.dataTimeline),
    updated_at: randomDate(config.dataTimeline)
  };
}

function generateAccount(customerId) {
  const accountTypes = ['CHECKING', 'SAVINGS', 'CREDIT', 'LOAN'];
  const accountType = randomChoice(accountTypes);
  
  return {
    customer_id: customerId,
    account_number: `ACC-2024-${String(customerId).padStart(6, '0')}`,
    account_type: accountType,
    balance: randomBetween(100, 50000),
    currency: 'USD',
    account_status: randomChoice(['ACTIVE', 'ACTIVE', 'ACTIVE', 'FROZEN']), // 75% active
    interest_rate: accountType === 'SAVINGS' ? randomBetween(1, 3) / 100 : 0,
    credit_limit: accountType === 'CREDIT' ? randomBetween(1000, 10000) : null,
    opened_date: randomDate(config.dataTimeline),
    closed_date: null,
    created_at: randomDate(config.dataTimeline),
    updated_at: randomDate(config.dataTimeline)
  };
}

function generateTransaction(accountId) {
  const transactionTypes = ['DEPOSIT', 'WITHDRAWAL', 'TRANSFER_IN', 'TRANSFER_OUT', 'PAYMENT', 'FEE'];
  const transactionType = randomChoice(transactionTypes);
  const amount = randomBetween(10, 2000);
  
  return {
    account_id: accountId,
    transaction_type: transactionType,
    amount: transactionType === 'WITHDRAWAL' || transactionType === 'TRANSFER_OUT' ? -amount : amount,
    currency: 'USD',
    description: `${transactionType.toLowerCase()} transaction`,
    reference_number: `TXN-${String(randomBetween(100000, 999999))}`,
    counterparty_account: Math.random() > 0.5 ? `ACC-${String(randomBetween(100000, 999999))}` : null,
    transaction_date: randomDate(config.dataTimeline),
    posted_date: randomDate(config.dataTimeline),
    status: randomChoice(['COMPLETED', 'COMPLETED', 'COMPLETED', 'PENDING']), // 75% completed
    created_at: randomDate(config.dataTimeline),
    updated_at: randomDate(config.dataTimeline)
  };
}

function generateAgreement(customerId, accountId) {
  const agreementTypes = ['LOAN', 'CREDIT_CARD', 'OVERDRAFT', 'INVESTMENT'];
  const agreementType = randomChoice(agreementTypes);
  const principalAmount = randomBetween(5000, 100000);
  
  return {
    customer_id: customerId,
    account_id: accountId,
    agreement_type: agreementType,
    agreement_number: `AGR-${String(randomBetween(100000, 999999))}`,
    principal_amount: principalAmount,
    current_balance: randomBetween(0, principalAmount),
    interest_rate: randomBetween(3, 15) / 100,
    term_months: randomBetween(12, 60),
    payment_amount: Math.floor(principalAmount / randomBetween(12, 60)),
    payment_frequency: randomChoice(['MONTHLY', 'QUARTERLY', 'ANNUALLY']),
    start_date: randomDate(config.dataTimeline),
    end_date: null,
    status: randomChoice(['ACTIVE', 'ACTIVE', 'ACTIVE', 'COMPLETED']), // 75% active
    created_at: randomDate(config.dataTimeline),
    updated_at: randomDate(config.dataTimeline)
  };
}

async function createTables(connection) {
  try {
    console.log('Creating database tables...');
    
    // Split the SQL into individual statements and execute them
    const statements = createTablesSQL
      .split(';')
      .map(stmt => stmt.trim())
      .filter(stmt => stmt.length > 0 && !stmt.startsWith('--'));
    
    for (const statement of statements) {
      if (statement.trim()) {
        await connection.execute(statement);
      }
    }
    
    console.log('Database tables created successfully!');
  } catch (error) {
    console.error('Error creating tables:', error);
    throw error;
  }
}

async function generateAndInsertData() {
  let connection;
  
  try {
    console.log('Connecting to MySQL database...');
    connection = await mysql.createConnection(dbConfig);
    
    // Create tables first
    await createTables(connection);
    
    console.log('Generating sample data...');
    
    // Generate customers
    const customers = [];
    for (let i = 1; i <= config.customers; i++) {
      customers.push(generateCustomer());
    }
    
    // Insert customers
    console.log(`Inserting ${customers.length} customers...`);
    for (const customer of customers) {
      await connection.execute(
        `INSERT INTO customers (first_name, last_name, email, phone, date_of_birth, 
         address_line1, address_line2, city, state, postal_code, country, 
         customer_status, created_at, updated_at) 
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [customer.first_name, customer.last_name, customer.email, customer.phone,
         customer.date_of_birth, customer.address_line1, customer.address_line2,
         customer.city, customer.state, customer.postal_code, customer.country,
         customer.customer_status, customer.created_at, customer.updated_at]
      );
    }
    
    // Generate accounts
    const accounts = [];
    for (let customerId = 1; customerId <= config.customers; customerId++) {
      const numAccounts = randomBetween(config.accountsPerCustomer.min, config.accountsPerCustomer.max);
      for (let j = 0; j < numAccounts; j++) {
        accounts.push(generateAccount(customerId));
      }
    }
    
    // Insert accounts
    console.log(`Inserting ${accounts.length} accounts...`);
    for (const account of accounts) {
      await connection.execute(
        `INSERT INTO accounts (customer_id, account_number, account_type, balance, 
         currency, account_status, interest_rate, credit_limit, opened_date, 
         closed_date, created_at, updated_at) 
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [account.customer_id, account.account_number, account.account_type, account.balance,
         account.currency, account.account_status, account.interest_rate, account.credit_limit,
         account.opened_date, account.closed_date, account.created_at, account.updated_at]
      );
    }
    
    // Generate transactions
    const transactions = [];
    for (const account of accounts) {
      for (let i = 0; i < config.transactionsPerAccount; i++) {
        transactions.push(generateTransaction(account.account_id));
      }
    }
    
    // Insert transactions
    console.log(`Inserting ${transactions.length} transactions...`);
    for (const transaction of transactions) {
      await connection.execute(
        `INSERT INTO transactions (account_id, transaction_type, amount, currency, 
         description, reference_number, counterparty_account, transaction_date, 
         posted_date, status, created_at, updated_at) 
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [transaction.account_id, transaction.transaction_type, transaction.amount,
         transaction.currency, transaction.description, transaction.reference_number,
         transaction.counterparty_account, transaction.transaction_date, transaction.posted_date,
         transaction.status, transaction.created_at, transaction.updated_at]
      );
    }
    
    // Generate agreements
    const agreements = [];
    const customersWithAgreements = Math.floor(config.customers * config.agreementsPercentage / 100);
    for (let i = 1; i <= customersWithAgreements; i++) {
      const customerAccounts = accounts.filter(acc => acc.customer_id === i);
      if (customerAccounts.length > 0) {
        const account = randomChoice(customerAccounts);
        agreements.push(generateAgreement(i, account.account_id));
      }
    }
    
    // Insert agreements
    console.log(`Inserting ${agreements.length} agreements...`);
    for (const agreement of agreements) {
      await connection.execute(
        `INSERT INTO agreements (customer_id, account_id, agreement_type, agreement_number, 
         principal_amount, current_balance, interest_rate, term_months, payment_amount, 
         payment_frequency, start_date, end_date, status, created_at, updated_at) 
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [agreement.customer_id, agreement.account_id, agreement.agreement_type,
         agreement.agreement_number, agreement.principal_amount, agreement.current_balance,
         agreement.interest_rate, agreement.term_months, agreement.payment_amount,
         agreement.payment_frequency, agreement.start_date, agreement.end_date,
         agreement.status, agreement.created_at, agreement.updated_at]
      );
    }
    
    console.log('Sample data generation completed successfully!');
    console.log(`Generated:`);
    console.log(`- ${customers.length} customers`);
    console.log(`- ${accounts.length} accounts`);
    console.log(`- ${transactions.length} transactions`);
    console.log(`- ${agreements.length} agreements`);
    
  } catch (error) {
    console.error('Error generating sample data:', error);
    process.exit(1);
  } finally {
    if (connection) {
      await connection.end();
    }
  }
}

// Run the script
if (require.main === module) {
  generateAndInsertData();
}

module.exports = { generateAndInsertData };

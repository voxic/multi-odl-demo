#!/usr/bin/env python3
"""
Sample data generation script for ODL Demo banking application.
Creates MySQL tables and populates them with realistic banking data.

Usage:
    # Option 1: With port-forward (recommended for local development)
    kubectl port-forward service/mysql-service 3306:3306 -n odl-demo &
    python3 scripts/generate-sample-data.py

    # Option 2: Direct execution in MySQL pod
    kubectl exec -it deployment/mysql -n odl-demo -- python3 -c "
    import sys
    sys.path.append('/tmp')
    exec(open('/tmp/generate-sample-data.py').read())
    "

    # Option 3: Copy script to pod and run
    kubectl cp scripts/generate-sample-data.py odl-demo/$(kubectl get pods -n odl-demo -l app=mysql -o jsonpath='{.items[0].metadata.name}'):/tmp/
    kubectl exec -it deployment/mysql -n odl-demo -- python3 /tmp/generate-sample-data.py
"""

import os
import random
import sys
import subprocess
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional
import mysql.connector
from mysql.connector import Error

# Database configuration
DB_CONFIG = {
    'host': os.getenv('MYSQL_HOST', 'localhost'),
    'port': int(os.getenv('MYSQL_PORT', 3306)),
    'user': os.getenv('MYSQL_USER', 'odl_user'),
    'password': os.getenv('MYSQL_PASSWORD', 'odl_password'),
    'database': os.getenv('MYSQL_DATABASE', 'banking')
}

# Sample data configuration
CONFIG = {
    'customers': 100,
    'accounts_per_customer': {'min': 1, 'max': 3},
    'transactions_per_account': 10,
    'agreements_percentage': 30,
    'data_timeline': 30  # days
}

# Sample data generators
FIRST_NAMES = ['John', 'Jane', 'Michael', 'Sarah', 'David', 'Emily', 'Robert', 'Jessica', 'William', 'Ashley']
LAST_NAMES = ['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis', 'Rodriguez', 'Martinez']
CITIES = ['New York', 'Los Angeles', 'Chicago', 'Houston', 'Phoenix', 'Philadelphia', 'San Antonio', 'San Diego', 'Dallas', 'San Jose']
STATES = ['NY', 'CA', 'IL', 'TX', 'AZ', 'PA', 'TX', 'CA', 'TX', 'CA']

# Table creation SQL
CREATE_TABLES_SQL = """
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

-- Create indexes for better performance (using individual statements for compatibility)
CREATE INDEX idx_customers_email ON customers(email);
CREATE INDEX idx_customers_status ON customers(customer_status);
CREATE INDEX idx_accounts_customer_id ON accounts(customer_id);
CREATE INDEX idx_accounts_type ON accounts(account_type);
CREATE INDEX idx_accounts_status ON accounts(account_status);
CREATE INDEX idx_transactions_account_id ON transactions(account_id);
CREATE INDEX idx_transactions_type ON transactions(transaction_type);
CREATE INDEX idx_transactions_date ON transactions(transaction_date);
CREATE INDEX idx_agreements_customer_id ON agreements(customer_id);
CREATE INDEX idx_agreements_account_id ON agreements(account_id);
CREATE INDEX idx_agreements_type ON agreements(agreement_type);
"""


def random_choice(array: List[Any]) -> Any:
    """Return a random element from the given array."""
    return random.choice(array)


def random_between(min_val: int, max_val: int) -> int:
    """Return a random integer between min_val and max_val (inclusive)."""
    return random.randint(min_val, max_val)


def random_date(days_ago: int) -> datetime:
    """Return a random datetime within the last days_ago days."""
    now = datetime.now()
    random_days = random.randint(0, days_ago)
    return now - timedelta(days=random_days)


def generate_customer(customer_id: int) -> Dict[str, Any]:
    """Generate a random customer record with unique email."""
    first_name = random_choice(FIRST_NAMES)
    last_name = random_choice(LAST_NAMES)
    # Ensure unique email by including customer_id
    email = f"{first_name.lower()}.{last_name.lower()}{customer_id}@email.com"
    
    return {
        'first_name': first_name,
        'last_name': last_name,
        'email': email,
        'phone': f"+1-555-{random_between(100, 999):03d}-{random_between(1000, 9999)}",
        'date_of_birth': random_date(365 * 50),  # Random date within last 50 years
        'address_line1': f"{random_between(1, 9999)} {random_choice(['Main', 'Oak', 'Pine', 'Cedar', 'Elm'])} St",
        'address_line2': f"Apt {random_between(1, 20)}{random_choice(['A', 'B', 'C'])}" if random.random() > 0.7 else None,
        'city': random_choice(CITIES),
        'state': random_choice(STATES),
        'postal_code': str(random_between(10000, 99999)),
        'country': 'USA',
        'customer_status': random_choice(['ACTIVE', 'ACTIVE', 'ACTIVE', 'INACTIVE']),  # 75% active
        'created_at': random_date(CONFIG['data_timeline']),
        'updated_at': random_date(CONFIG['data_timeline'])
    }


def generate_account(customer_id: int, account_counter: int) -> Dict[str, Any]:
    """Generate a random account record for the given customer."""
    account_types = ['CHECKING', 'SAVINGS', 'CREDIT', 'LOAN']
    account_type = random_choice(account_types)
    
    return {
        'customer_id': customer_id,
        'account_number': f"ACC-2024-{customer_id:06d}-{account_counter:02d}",
        'account_type': account_type,
        'balance': random_between(100, 50000),
        'currency': 'USD',
        'account_status': random_choice(['ACTIVE', 'ACTIVE', 'ACTIVE', 'FROZEN']),  # 75% active
        'interest_rate': random_between(1, 3) / 100 if account_type == 'SAVINGS' else 0,
        'credit_limit': random_between(1000, 10000) if account_type == 'CREDIT' else None,
        'opened_date': random_date(CONFIG['data_timeline']),
        'closed_date': None,
        'created_at': random_date(CONFIG['data_timeline']),
        'updated_at': random_date(CONFIG['data_timeline'])
    }


def generate_transaction(account_id: int) -> Dict[str, Any]:
    """Generate a random transaction record for the given account."""
    transaction_types = ['DEPOSIT', 'WITHDRAWAL', 'TRANSFER_IN', 'TRANSFER_OUT', 'PAYMENT', 'FEE']
    transaction_type = random_choice(transaction_types)
    amount = random_between(10, 2000)
    
    return {
        'account_id': account_id,
        'transaction_type': transaction_type,
        'amount': -amount if transaction_type in ['WITHDRAWAL', 'TRANSFER_OUT'] else amount,
        'currency': 'USD',
        'description': f"{transaction_type.lower()} transaction",
        'reference_number': f"TXN-{random_between(100000, 999999)}",
        'counterparty_account': f"ACC-{random_between(100000, 999999)}" if random.random() > 0.5 else None,
        'transaction_date': random_date(CONFIG['data_timeline']),
        'posted_date': random_date(CONFIG['data_timeline']),
        'status': random_choice(['COMPLETED', 'COMPLETED', 'COMPLETED', 'PENDING']),  # 75% completed
        'created_at': random_date(CONFIG['data_timeline']),
        'updated_at': random_date(CONFIG['data_timeline'])
    }


def generate_agreement(customer_id: int, account_id: int, agreement_counter: int) -> Dict[str, Any]:
    """Generate a random agreement record for the given customer and account."""
    agreement_types = ['LOAN', 'CREDIT_CARD', 'OVERDRAFT', 'INVESTMENT']
    agreement_type = random_choice(agreement_types)
    principal_amount = random_between(5000, 100000)
    
    return {
        'customer_id': customer_id,
        'account_id': account_id,
        'agreement_type': agreement_type,
        'agreement_number': f"AGR-{customer_id:06d}-{agreement_counter:03d}",
        'principal_amount': principal_amount,
        'current_balance': random_between(0, principal_amount),
        'interest_rate': random_between(3, 15) / 100,
        'term_months': random_between(12, 60),
        'payment_amount': principal_amount // random_between(12, 60),
        'payment_frequency': random_choice(['MONTHLY', 'QUARTERLY', 'ANNUALLY']),
        'start_date': random_date(CONFIG['data_timeline']),
        'end_date': None,
        'status': random_choice(['ACTIVE', 'ACTIVE', 'ACTIVE', 'COMPLETED']),  # 75% active
        'created_at': random_date(CONFIG['data_timeline']),
        'updated_at': random_date(CONFIG['data_timeline'])
    }


def check_kubernetes_environment() -> bool:
    """Check if we're running in a Kubernetes environment."""
    return os.path.exists('/var/run/secrets/kubernetes.io/serviceaccount')


def check_mysql_connection() -> bool:
    """Check if MySQL is accessible."""
    try:
        connection = mysql.connector.connect(**DB_CONFIG)
        connection.close()
        return True
    except Error:
        return False


def print_connection_help():
    """Print helpful connection instructions."""
    print("\n" + "="*60)
    print("MYSQL CONNECTION HELP")
    print("="*60)
    print("The script cannot connect to MySQL. Here are your options:\n")
    
    print("OPTION 1: Port Forward (Recommended)")
    print("Run this in a separate terminal:")
    print("  kubectl port-forward service/mysql-service 3306:3306 -n odl-demo")
    print("Then run this script again.\n")
    
    print("OPTION 2: Run inside MySQL pod")
    print("Copy the script to the pod and run it there:")
    print("  kubectl cp scripts/generate-sample-data.py odl-demo/$(kubectl get pods -n odl-demo -l app=mysql -o jsonpath='{.items[0].metadata.name}'):/tmp/")
    print("  kubectl exec -it deployment/mysql -n odl-demo -- python3 /tmp/generate-sample-data.py\n")
    
    print("OPTION 3: Use kubectl exec with inline script")
    print("  kubectl exec -it deployment/mysql -n odl-demo -- python3 -c \"")
    print("  import sys, os, random, mysql.connector")
    print("  # ... (copy the script content here)")
    print("  \"\n")
    
    print("OPTION 4: Set environment variables for different host")
    print("  export MYSQL_HOST=mysql-service.odl-demo.svc.cluster.local")
    print("  python3 scripts/generate-sample-data.py\n")
    
    print("Current connection config:")
    print(f"  Host: {DB_CONFIG['host']}")
    print(f"  Port: {DB_CONFIG['port']}")
    print(f"  Database: {DB_CONFIG['database']}")
    print(f"  User: {DB_CONFIG['user']}")
    print("="*60)


def create_tables(cursor) -> None:
    """Create database tables."""
    try:
        print("Creating database tables...")
        
        # Split the SQL into individual statements and execute them
        statements = [stmt.strip() for stmt in CREATE_TABLES_SQL.split(';') 
                     if stmt.strip() and not stmt.strip().startswith('--')]
        
        for statement in statements:
            if statement:
                try:
                    cursor.execute(statement)
                except Error as e:
                    # If it's an index creation error, it might already exist
                    if "Duplicate key name" in str(e) or "already exists" in str(e):
                        print(f"Index already exists, skipping: {statement[:50]}...")
                        continue
                    else:
                        print(f"Error executing statement: {statement}")
                        print(f"Error: {e}")
                        raise
        
        print("Database tables created successfully!")
    except Error as e:
        print(f"Error creating tables: {e}")
        raise


def generate_and_insert_data() -> None:
    """Main function to generate and insert sample data."""
    connection = None
    
    try:
        print("Connecting to MySQL database...")
        print(f"Connection details: {DB_CONFIG['user']}@{DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['database']}")
        
        # Check if we can connect to MySQL
        if not check_mysql_connection():
            print_connection_help()
            sys.exit(1)
        
        connection = mysql.connector.connect(**DB_CONFIG)
        cursor = connection.cursor()
        
        # Create tables first
        create_tables(cursor)
        
        print("Generating sample data...")
        
        # Generate customers
        customers = []
        for i in range(1, CONFIG['customers'] + 1):
            customers.append(generate_customer(i))
        
        # Insert customers
        print(f"Inserting {len(customers)} customers...")
        customer_insert_query = """
        INSERT INTO customers (first_name, last_name, email, phone, date_of_birth, 
                              address_line1, address_line2, city, state, postal_code, country, 
                              customer_status, created_at, updated_at) 
        VALUES (%(first_name)s, %(last_name)s, %(email)s, %(phone)s,
                %(date_of_birth)s, %(address_line1)s, %(address_line2)s,
                %(city)s, %(state)s, %(postal_code)s, %(country)s,
                %(customer_status)s, %(created_at)s, %(updated_at)s)
        """
        
        inserted_customer_ids = set()
        for customer in customers:
            try:
                cursor.execute(customer_insert_query, customer)
                # Get the inserted customer ID
                cursor.execute("SELECT LAST_INSERT_ID()")
                customer_id = cursor.fetchone()[0]
                inserted_customer_ids.add(customer_id)
            except Error as e:
                if "Duplicate entry" in str(e):
                    print(f"Skipping duplicate customer: {customer['email']}")
                    # Try to find existing customer ID
                    cursor.execute("SELECT customer_id FROM customers WHERE email = %s", (customer['email'],))
                    result = cursor.fetchone()
                    if result:
                        inserted_customer_ids.add(result[0])
                    continue
                else:
                    raise
        
        print(f"Successfully processed {len(inserted_customer_ids)} customers")
        
        # Generate accounts only for customers that exist
        accounts = []
        for customer_id in inserted_customer_ids:
            num_accounts = random_between(CONFIG['accounts_per_customer']['min'], 
                                        CONFIG['accounts_per_customer']['max'])
            for account_counter in range(1, num_accounts + 1):
                accounts.append(generate_account(customer_id, account_counter))
        
        # Generate agreements only for customers that have accounts
        agreements = []
        customers_with_agreements = int(len(inserted_customer_ids) * CONFIG['agreements_percentage'] / 100)
        agreement_counter = 1
        processed_customers = 0
        
        # First, we need to insert accounts to get their IDs
        print(f"Inserting {len(accounts)} accounts...")
        account_insert_query = """
        INSERT INTO accounts (customer_id, account_number, account_type, balance, 
                             currency, account_status, interest_rate, credit_limit, opened_date, 
                             closed_date, created_at, updated_at) 
        VALUES (%(customer_id)s, %(account_number)s, %(account_type)s, %(balance)s,
                %(currency)s, %(account_status)s, %(interest_rate)s, %(credit_limit)s,
                %(opened_date)s, %(closed_date)s, %(created_at)s, %(updated_at)s)
        """
        
        inserted_accounts = []
        for account in accounts:
            try:
                cursor.execute(account_insert_query, account)
                # Get the inserted account ID
                cursor.execute("SELECT LAST_INSERT_ID()")
                account_id = cursor.fetchone()[0]
                account['account_id'] = account_id  # Add the ID to the account dict
                inserted_accounts.append(account)
            except Error as e:
                if "Duplicate entry" in str(e):
                    print(f"Skipping duplicate account: {account['account_number']}")
                    continue
                else:
                    raise
        
        print(f"Successfully processed {len(inserted_accounts)} accounts")
        
        # Generate transactions using inserted accounts
        transactions = []
        for account in inserted_accounts:
            for _ in range(CONFIG['transactions_per_account']):
                transactions.append(generate_transaction(account['account_id']))
        
        # Insert transactions
        print(f"Inserting {len(transactions)} transactions...")
        transaction_insert_query = """
        INSERT INTO transactions (account_id, transaction_type, amount, currency, 
                                description, reference_number, counterparty_account, transaction_date, 
                                posted_date, status, created_at, updated_at) 
        VALUES (%(account_id)s, %(transaction_type)s, %(amount)s,
                %(currency)s, %(description)s, %(reference_number)s,
                %(counterparty_account)s, %(transaction_date)s, %(posted_date)s,
                %(status)s, %(created_at)s, %(updated_at)s)
        """
        
        for transaction in transactions:
            cursor.execute(transaction_insert_query, transaction)
        
        # Now generate agreements using the inserted accounts
        for customer_id in inserted_customer_ids:
            if processed_customers >= customers_with_agreements:
                break
            customer_accounts = [acc for acc in inserted_accounts if acc['customer_id'] == customer_id]
            if customer_accounts:
                account = random_choice(customer_accounts)
                agreements.append(generate_agreement(customer_id, account['account_id'], agreement_counter))
                agreement_counter += 1
                processed_customers += 1
        
        # Insert agreements
        print(f"Inserting {len(agreements)} agreements...")
        agreement_insert_query = """
        INSERT INTO agreements (customer_id, account_id, agreement_type, agreement_number, 
                               principal_amount, current_balance, interest_rate, term_months, payment_amount, 
                               payment_frequency, start_date, end_date, status, created_at, updated_at) 
        VALUES (%(customer_id)s, %(account_id)s, %(agreement_type)s,
                %(agreement_number)s, %(principal_amount)s, %(current_balance)s,
                %(interest_rate)s, %(term_months)s, %(payment_amount)s,
                %(payment_frequency)s, %(start_date)s, %(end_date)s,
                %(status)s, %(created_at)s, %(updated_at)s)
        """
        
        for agreement in agreements:
            try:
                cursor.execute(agreement_insert_query, agreement)
            except Error as e:
                if "Duplicate entry" in str(e):
                    print(f"Skipping duplicate agreement: {agreement['agreement_number']}")
                    continue
                else:
                    raise
        
        # Commit all changes
        connection.commit()
        
        print("Sample data generation completed successfully!")
        print(f"Generated:")
        print(f"- {len(customers)} customers")
        print(f"- {len(accounts)} accounts")
        print(f"- {len(transactions)} transactions")
        print(f"- {len(agreements)} agreements")
        
    except Error as e:
        print(f"Error generating sample data: {e}")
        if connection:
            connection.rollback()
        sys.exit(1)
    finally:
        if connection and connection.is_connected():
            cursor.close()
            connection.close()


if __name__ == "__main__":
    generate_and_insert_data()

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
import argparse
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional, Iterable, Tuple
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
_env_use_faker = os.getenv('ODL_USE_FAKER')
CONFIG = {
    'customers': int(os.getenv('ODL_CUSTOMERS', 100)),
    'accounts_per_customer': {
        'min': int(os.getenv('ODL_ACCOUNTS_PER_CUSTOMER_MIN', 1)),
        'max': int(os.getenv('ODL_ACCOUNTS_PER_CUSTOMER_MAX', 3))
    },
    'transactions_per_account': int(os.getenv('ODL_TX_PER_ACCOUNT', 100)),
    'agreements_percentage': int(os.getenv('ODL_AGREEMENTS_PERCENT', 80)),
    'data_timeline': int(os.getenv('ODL_TIMELINE_DAYS', 30)),  # days
    'batch_size': int(os.getenv('ODL_BATCH_SIZE', 1000)),
    'random_seed': os.getenv('ODL_RANDOM_SEED'),
    # Default to True when env var is not provided; otherwise respect truthy/falsey value
    'use_faker': (True if _env_use_faker is None else _env_use_faker in ('1', 'true', 'True'))
}

# Sample data generators
FIRST_NAMES = [
    'Liam', 'Noah', 'Oliver', 'Elijah', 'James', 'William', 'Benjamin', 'Lucas', 'Henry', 'Theodore',
    'Olivia', 'Emma', 'Charlotte', 'Amelia', 'Sophia', 'Isabella', 'Mia', 'Evelyn', 'Harper', 'Luna',
    'Ava', 'Mason', 'Logan', 'Jacob', 'Michael', 'Daniel', 'Matthew', 'Sebastian', 'Jack', 'Aiden',
    'Emily', 'Abigail', 'Ella', 'Elizabeth', 'Sofia', 'Avery', 'Scarlett', 'Madison', 'Camila', 'Aria'
]
LAST_NAMES = [
    'Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis', 'Rodriguez', 'Martinez',
    'Hernandez', 'Lopez', 'Gonzalez', 'Wilson', 'Anderson', 'Thomas', 'Taylor', 'Moore', 'Jackson', 'Martin',
    'Lee', 'Perez', 'Thompson', 'White', 'Harris', 'Sanchez', 'Clark', 'Ramirez', 'Lewis', 'Robinson',
    'Walker', 'Young', 'Allen', 'King', 'Wright', 'Scott', 'Torres', 'Nguyen', 'Hill', 'Flores'
]
CITIES = [
    'New York', 'Los Angeles', 'Chicago', 'Houston', 'Phoenix', 'Philadelphia', 'San Antonio', 'San Diego',
    'Dallas', 'San Jose', 'Austin', 'Jacksonville', 'Fort Worth', 'Columbus', 'Charlotte', 'San Francisco',
    'Indianapolis', 'Seattle', 'Denver', 'Washington'
]
STATES = [
    'NY', 'CA', 'IL', 'TX', 'AZ', 'PA', 'FL', 'OH', 'NC', 'WA', 'CO', 'DC'
]

TRANSACTION_DESCRIPTIONS = [
    'ATM withdrawal', 'Salary deposit', 'Online transfer', 'Bill payment', 'POS purchase', 'Wire transfer',
    'Subscription fee', 'Service charge', 'Card payment', 'Refund', 'Cash deposit', 'Mobile payment'
]

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


def chunked(items: Iterable[Any], chunk_size: int) -> Iterable[List[Any]]:
    """Yield lists of size chunk_size from items."""
    chunk: List[Any] = []
    for item in items:
        chunk.append(item)
        if len(chunk) >= chunk_size:
            yield chunk
            chunk = []
    if chunk:
        yield chunk


def get_enum_values(cursor, table_name: str, column_name: str) -> List[str]:
    """Return the ENUM options for a given table.column, or empty list if not enum/unknown."""
    try:
        cursor.execute(f"SHOW COLUMNS FROM {table_name} LIKE %s", (column_name,))
        row = cursor.fetchone()
        if not row:
            return []
        # MySQL returns: Field, Type, Null, Key, Default, Extra
        col_type = row[1]
        if not col_type.lower().startswith('enum('):
            return []
        # enum('A','B','C') → [A,B,C]
        inside = col_type[col_type.find('(')+1:col_type.rfind(')')]
        parts = [p.strip().strip("'") for p in inside.split(',')]
        return parts
    except Error:
        return []


def normalize_enum_value(value: str, allowed: List[str], default_fallback: Optional[str] = None) -> str:
    """Return a value present in allowed, mapping common variants when necessary."""
    if not allowed:
        return value
    if value in allowed:
        return value
    # Common American/British spelling difference
    if value == 'CANCELLED' and 'CANCELED' in allowed:
        return 'CANCELED'
    if value == 'CANCELED' and 'CANCELLED' in allowed:
        return 'CANCELLED'
    # Try case-insensitive match
    lower_map = {a.lower(): a for a in allowed}
    if value.lower() in lower_map:
        return lower_map[value.lower()]
    # Fallback to provided default or first allowed
    if default_fallback and default_fallback in allowed:
        return default_fallback
    return allowed[0]


def generate_customer(customer_id: int) -> Dict[str, Any]:
    """Generate a random customer record with unique email."""
    global FAKE
    if FAKE is not None:
        first_name = FAKE.first_name()
        last_name = FAKE.last_name()
        # Ensure unique email by including customer_id to avoid collisions
        email = f"{FAKE.user_name()}.{customer_id}@{FAKE.free_email_domain()}"
        addr = FAKE.address().split('\n')
        address_line1 = addr[0][:100]
        address_line2 = addr[1][:100] if len(addr) > 1 else None
        city = FAKE.city()
        state = FAKE.state_abbr()
        postal_code = FAKE.postcode()[:10]
        phone = FAKE.phone_number()
        dob = FAKE.date_of_birth(minimum_age=18, maximum_age=85)
    else:
        first_name = random_choice(FIRST_NAMES)
        last_name = random_choice(LAST_NAMES)
        # Ensure unique email by including customer_id
        email = f"{first_name.lower()}.{last_name.lower()}{customer_id}@email.com"
        address_line1 = f"{random_between(1, 9999)} {random_choice(['Main', 'Oak', 'Pine', 'Cedar', 'Elm'])} St"
        address_line2 = f"Apt {random_between(1, 20)}{random_choice(['A', 'B', 'C'])}" if random.random() > 0.7 else None
        city = random_choice(CITIES)
        state = random_choice(STATES)
        postal_code = str(random_between(10000, 99999))
        phone = f"+1-{random_choice(['212','305','312','415','512','617','646','702','808','818','925'])}-{random_between(100, 999):03d}-{random_between(1000, 9999)}"
        dob = random_date(365 * 50)
    
    return {
        'first_name': first_name,
        'last_name': last_name,
        'email': email,
        'phone': phone,
        'date_of_birth': dob,  # date object or datetime accepted by connector
        'address_line1': address_line1,
        'address_line2': address_line2,
        'city': city,
        'state': state,
        'postal_code': postal_code,
        'country': 'USA',
        'customer_status': random.choices(['ACTIVE', 'INACTIVE', 'SUSPENDED'], weights=[80, 15, 5])[0],
        'created_at': random_date(CONFIG['data_timeline']),
        'updated_at': random_date(CONFIG['data_timeline'])
    }


def generate_account(customer_id: int, account_counter: int) -> Dict[str, Any]:
    """Generate a random account record for the given customer."""
    account_type = random.choices(
        ['CHECKING', 'SAVINGS', 'CREDIT', 'LOAN'], weights=[55, 25, 15, 5]
    )[0]
    
    return {
        'customer_id': customer_id,
        'account_number': f"ACC-2024-{customer_id:06d}-{account_counter:02d}",
        'account_type': account_type,
        'balance': random_between(100, 50000) if account_type != 'LOAN' else -random_between(1000, 20000),
        'currency': 'USD',
        'account_status': random.choices(['ACTIVE', 'FROZEN', 'CLOSED'], weights=[80, 15, 5])[0],
        'interest_rate': random_between(1, 3) / 100 if account_type == 'SAVINGS' else 0,
        'credit_limit': random_between(1000, 10000) if account_type == 'CREDIT' else None,
        'opened_date': random_date(CONFIG['data_timeline']),
        'closed_date': None,
        'created_at': random_date(CONFIG['data_timeline']),
        'updated_at': random_date(CONFIG['data_timeline'])
    }


def generate_transaction(account_id: int) -> Dict[str, Any]:
    """Generate a random transaction record for the given account."""
    transaction_type = random.choices(
        ['DEPOSIT', 'WITHDRAWAL', 'TRANSFER_IN', 'TRANSFER_OUT', 'PAYMENT', 'FEE'],
        weights=[25, 25, 15, 15, 15, 5]
    )[0]
    amount = random_between(5, 5000)
    
    return {
        'account_id': account_id,
        'transaction_type': transaction_type,
        'amount': -amount if transaction_type in ['WITHDRAWAL', 'TRANSFER_OUT'] else amount,
        'currency': 'USD',
        'description': random_choice(TRANSACTION_DESCRIPTIONS),
        'reference_number': f"TXN-{random_between(100000, 999999)}",
        'counterparty_account': f"ACC-{random_between(100000, 999999)}" if random.random() > 0.5 else None,
        'transaction_date': random_date(CONFIG['data_timeline']),
        'posted_date': random_date(CONFIG['data_timeline']),
        'status': random.choices(['COMPLETED', 'PENDING', 'FAILED', 'CANCELLED'], weights=[75, 15, 8, 2])[0],
        'created_at': random_date(CONFIG['data_timeline']),
        'updated_at': random_date(CONFIG['data_timeline'])
    }


def generate_agreement(customer_id: int, account_id: int, agreement_counter: int) -> Dict[str, Any]:
    """Generate a random agreement record for the given customer and account."""
    agreement_type = random.choices(['LOAN', 'CREDIT_CARD', 'OVERDRAFT', 'INVESTMENT'], weights=[60, 25, 10, 5])[0]
    principal_amount = random_between(2000, 200000)
    
    return {
        'customer_id': customer_id,
        'account_id': account_id,
        'agreement_type': agreement_type,
        'agreement_number': f"AGR-{customer_id:06d}-{agreement_counter:03d}",
        'principal_amount': principal_amount,
        'current_balance': random_between(0, principal_amount),
        'interest_rate': random_between(3, 25) / 100,
        'term_months': random_between(12, 60),
        'payment_amount': principal_amount // random_between(12, 60),
        'payment_frequency': random_choice(['MONTHLY', 'QUARTERLY', 'ANNUALLY']),
        'start_date': random_date(CONFIG['data_timeline']),
        'end_date': None,
        'status': random.choices(['ACTIVE', 'COMPLETED', 'DEFAULTED', 'CANCELLED'], weights=[75, 15, 5, 5])[0],
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
        
        # Optional seeding
        if CONFIG['random_seed'] is not None:
            try:
                random.seed(int(CONFIG['random_seed']))
            except ValueError:
                random.seed(CONFIG['random_seed'])
        # Optional Faker setup
        global FAKE
        FAKE = None
        if CONFIG.get('use_faker'):
            try:
                from faker import Faker  # type: ignore
                FAKE = Faker('en_US')
                if CONFIG['random_seed'] is not None:
                    try:
                        FAKE.seed_instance(int(CONFIG['random_seed']))
                    except ValueError:
                        FAKE.seed_instance(CONFIG['random_seed'])
                print("Faker enabled for customer data generation")
            except Exception as e:
                print(f"Faker requested but not available ({e}); continuing without it.")

        # Generate customers
        customers = [generate_customer(i) for i in range(1, CONFIG['customers'] + 1)]

        # Insert customers in batches
        print(f"Inserting {len(customers)} customers (batch size {CONFIG['batch_size']})...")
        customer_insert_query = (
            "INSERT IGNORE INTO customers (first_name, last_name, email, phone, date_of_birth, "
            "address_line1, address_line2, city, state, postal_code, country, "
            "customer_status, created_at, updated_at) "
            "VALUES (%(first_name)s, %(last_name)s, %(email)s, %(phone)s, %(date_of_birth)s, %(address_line1)s, %(address_line2)s, %(city)s, %(state)s, %(postal_code)s, %(country)s, %(customer_status)s, %(created_at)s, %(updated_at)s)"
        )

        for batch in chunked(customers, CONFIG['batch_size']):
            cursor.executemany(customer_insert_query, batch)

        # Map emails to customer IDs
        emails = [c['email'] for c in customers]
        inserted_customer_ids: set[int] = set()
        email_to_id: Dict[str, int] = {}
        for batch in chunked(emails, CONFIG['batch_size']):
            placeholders = ",".join(["%s"] * len(batch))
            cursor.execute(f"SELECT customer_id, email FROM customers WHERE email IN ({placeholders})", batch)
            for cid, email in cursor.fetchall():
                inserted_customer_ids.add(cid)
                email_to_id[email] = cid

        print(f"Customers available: {len(inserted_customer_ids)}")
        
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
        print(f"Inserting {len(accounts)} accounts (batch size {CONFIG['batch_size']})...")
        account_insert_query = (
            "INSERT IGNORE INTO accounts (customer_id, account_number, account_type, balance, "
            "currency, account_status, interest_rate, credit_limit, opened_date, closed_date, created_at, updated_at) "
            "VALUES (%(customer_id)s, %(account_number)s, %(account_type)s, %(balance)s, %(currency)s, %(account_status)s, %(interest_rate)s, %(credit_limit)s, %(opened_date)s, %(closed_date)s, %(created_at)s, %(updated_at)s)"
        )

        for batch in chunked(accounts, CONFIG['batch_size']):
            cursor.executemany(account_insert_query, batch)

        # Map account_number to account_id
        account_numbers = [a['account_number'] for a in accounts]
        accnum_to_id: Dict[str, int] = {}
        for batch in chunked(account_numbers, CONFIG['batch_size']):
            placeholders = ",".join(["%s"] * len(batch))
            cursor.execute(f"SELECT account_id, account_number FROM accounts WHERE account_number IN ({placeholders})", batch)
            for aid, accnum in cursor.fetchall():
                accnum_to_id[accnum] = aid

        inserted_accounts = []
        for a in accounts:
            aid = accnum_to_id.get(a['account_number'])
            if aid:
                a['account_id'] = aid
                inserted_accounts.append(a)

        print(f"Accounts available: {len(inserted_accounts)}")
        
        # Generate transactions using inserted accounts
        transactions = []
        for account in inserted_accounts:
            for _ in range(CONFIG['transactions_per_account']):
                transactions.append(generate_transaction(account['account_id']))
        
        # Insert transactions
        print(f"Inserting {len(transactions)} transactions (batch size {CONFIG['batch_size']})...")
        transaction_insert_query = """
        INSERT INTO transactions (account_id, transaction_type, amount, currency, 
                                description, reference_number, counterparty_account, transaction_date, 
                                posted_date, status, created_at, updated_at) 
        VALUES (%(account_id)s, %(transaction_type)s, %(amount)s,
                %(currency)s, %(description)s, %(reference_number)s,
                %(counterparty_account)s, %(transaction_date)s, %(posted_date)s,
                %(status)s, %(created_at)s, %(updated_at)s)
        """
        
        for batch in chunked(transactions, CONFIG['batch_size']):
            # Normalize status values against live ENUM
            allowed_status = get_enum_values(cursor, 'transactions', 'status')
            if allowed_status:
                for item in batch:
                    item['status'] = normalize_enum_value(item['status'], allowed_status, default_fallback='COMPLETED')
            cursor.executemany(transaction_insert_query, batch)
        
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
        print(f"Inserting {len(agreements)} agreements (batch size {CONFIG['batch_size']})...")
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
        
        for batch in chunked(agreements, CONFIG['batch_size']):
            try:
                allowed_status = get_enum_values(cursor, 'agreements', 'status')
                if allowed_status:
                    for item in batch:
                        item['status'] = normalize_enum_value(item['status'], allowed_status, default_fallback='ACTIVE')
                cursor.executemany(agreement_insert_query, batch)
            except Error as e:
                if "Duplicate entry" in str(e):
                    pass
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
    parser = argparse.ArgumentParser(description="Generate ODL Demo sample data")
    parser.add_argument("--customers", type=int, help="Number of customers to generate")
    parser.add_argument("--accounts-min", type=int, help="Min accounts per customer")
    parser.add_argument("--accounts-max", type=int, help="Max accounts per customer")
    parser.add_argument("--tx-per-account", type=int, help="Transactions per account")
    parser.add_argument("--agreements-percent", type=int, help="Percent of customers with agreements")
    parser.add_argument("--timeline-days", type=int, help="Timeline window in days")
    parser.add_argument("--batch-size", type=int, help="Insert batch size")
    parser.add_argument("--seed", type=str, help="Random seed for reproducibility")
    parser.add_argument("--use-faker", action="store_true", help="Use Faker for customer data")
    parser.add_argument("--no-faker", action="store_true", help="Disable Faker and use built-in generator")
    args = parser.parse_args()

    if args.customers is not None:
        CONFIG['customers'] = args.customers
    if args.accounts_min is not None:
        CONFIG['accounts_per_customer']['min'] = args.accounts_min
    if args.accounts_max is not None:
        CONFIG['accounts_per_customer']['max'] = args.accounts_max
    if args.tx_per_account is not None:
        CONFIG['transactions_per_account'] = args.tx_per_account
    if args.agreements_percent is not None:
        CONFIG['agreements_percentage'] = args.agreements_percent
    if args.timeline_days is not None:
        CONFIG['data_timeline'] = args.timeline_days
    if args.batch_size is not None:
        CONFIG['batch_size'] = args.batch_size
    if args.seed is not None:
        CONFIG['random_seed'] = args.seed
    if args.use_faker:
        CONFIG['use_faker'] = True
    if args.no_faker:
        CONFIG['use_faker'] = False

    # Basic validation
    CONFIG['accounts_per_customer']['min'] = max(0, CONFIG['accounts_per_customer']['min'])
    CONFIG['accounts_per_customer']['max'] = max(CONFIG['accounts_per_customer']['min'], CONFIG['accounts_per_customer']['max'])
    CONFIG['agreements_percentage'] = min(max(CONFIG['agreements_percentage'], 0), 100)
    CONFIG['batch_size'] = max(100, CONFIG['batch_size'])

    print(f"Config: customers={CONFIG['customers']}, accounts=[{CONFIG['accounts_per_customer']['min']}-{CONFIG['accounts_per_customer']['max']}], tx/account={CONFIG['transactions_per_account']}, agreements%={CONFIG['agreements_percentage']}, days={CONFIG['data_timeline']}, batch={CONFIG['batch_size']}, faker={CONFIG['use_faker']}")

    generate_and_insert_data()

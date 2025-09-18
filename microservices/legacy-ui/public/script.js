// Legacy Banking System JavaScript

let customers = [];
let accounts = [];
let transactions = [];
let currentCustomerId = null;
let currentAccountId = null;

// Initialize the application
document.addEventListener('DOMContentLoaded', function() {
    updateCurrentTime();
    setInterval(updateCurrentTime, 1000);
    loadCustomers();
});

// Update current time display
function updateCurrentTime() {
    const now = new Date();
    const timeString = now.toLocaleString('en-US', {
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit'
    });
    document.getElementById('current-time').textContent = timeString;
}

// Navigation functions
function showSection(sectionName) {
    // Hide all sections
    document.querySelectorAll('.section').forEach(section => {
        section.classList.remove('active');
    });
    
    // Remove active class from all nav buttons
    document.querySelectorAll('.nav-btn').forEach(btn => {
        btn.classList.remove('active');
    });
    
    // Show selected section
    document.getElementById(sectionName + '-section').classList.add('active');
    
    // Add active class to clicked button
    event.target.classList.add('active');
    
    // Load data for the section
    if (sectionName === 'customers') {
        loadCustomers();
    } else if (sectionName === 'accounts') {
        loadCustomerSelect();
    } else if (sectionName === 'transactions') {
        loadAccountSelect();
    }
}

// Load customers
async function loadCustomers() {
    try {
        const response = await fetch('/api/customers');
        customers = await response.json();
        displayCustomers(customers);
    } catch (error) {
        console.error('Error loading customers:', error);
        showError('Failed to load customers');
    }
}

// Display customers in table
function displayCustomers(customerList) {
    const tbody = document.getElementById('customers-table');
    
    if (customerList.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7" class="loading">No customers found</td></tr>';
        return;
    }
    
    tbody.innerHTML = customerList.map(customer => `
        <tr>
            <td>${customer.customer_id}</td>
            <td>${customer.first_name} ${customer.last_name}</td>
            <td>${customer.email}</td>
            <td>${customer.phone || 'N/A'}</td>
            <td><span class="status-${customer.customer_status.toLowerCase()}">${customer.customer_status}</span></td>
            <td>${customer.city || 'N/A'}</td>
            <td>
                <button class="action-btn edit" onclick="editCustomer(${customer.customer_id})">Edit</button>
                <button class="action-btn" onclick="viewCustomerAccounts(${customer.customer_id})">Accounts</button>
            </td>
        </tr>
    `).join('');
}

// Search customers
function searchCustomers() {
    const searchTerm = document.getElementById('customer-search').value.toLowerCase();
    const filteredCustomers = customers.filter(customer => 
        customer.first_name.toLowerCase().includes(searchTerm) ||
        customer.last_name.toLowerCase().includes(searchTerm) ||
        customer.email.toLowerCase().includes(searchTerm) ||
        customer.phone?.toLowerCase().includes(searchTerm)
    );
    displayCustomers(filteredCustomers);
}

// Edit customer
async function editCustomer(customerId) {
    try {
        const response = await fetch(`/api/customers/${customerId}`);
        const customer = await response.json();
        
        // Populate form
        document.getElementById('edit-customer-id').value = customer.customer_id;
        document.getElementById('edit-first-name').value = customer.first_name;
        document.getElementById('edit-last-name').value = customer.last_name;
        document.getElementById('edit-email').value = customer.email;
        document.getElementById('edit-phone').value = customer.phone || '';
        document.getElementById('edit-address1').value = customer.address_line1 || '';
        document.getElementById('edit-address2').value = customer.address_line2 || '';
        document.getElementById('edit-city').value = customer.city || '';
        document.getElementById('edit-state').value = customer.state || '';
        document.getElementById('edit-postal').value = customer.postal_code || '';
        document.getElementById('edit-country').value = customer.country || 'USA';
        document.getElementById('edit-status').value = customer.customer_status;
        
        // Show modal
        document.getElementById('edit-customer-modal').style.display = 'block';
    } catch (error) {
        console.error('Error loading customer:', error);
        showError('Failed to load customer details');
    }
}

// Save customer changes
document.getElementById('edit-customer-form').addEventListener('submit', async function(e) {
    e.preventDefault();
    
    const customerId = document.getElementById('edit-customer-id').value;
    const formData = {
        first_name: document.getElementById('edit-first-name').value,
        last_name: document.getElementById('edit-last-name').value,
        email: document.getElementById('edit-email').value,
        phone: document.getElementById('edit-phone').value,
        address_line1: document.getElementById('edit-address1').value,
        address_line2: document.getElementById('edit-address2').value,
        city: document.getElementById('edit-city').value,
        state: document.getElementById('edit-state').value,
        postal_code: document.getElementById('edit-postal').value,
        country: document.getElementById('edit-country').value,
        customer_status: document.getElementById('edit-status').value
    };
    
    try {
        const response = await fetch(`/api/customers/${customerId}`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(formData)
        });
        
        if (response.ok) {
            showSuccess('Customer updated successfully');
            closeModal('edit-customer-modal');
            loadCustomers();
        } else {
            const error = await response.json();
            showError(error.error || 'Failed to update customer');
        }
    } catch (error) {
        console.error('Error updating customer:', error);
        showError('Failed to update customer');
    }
});

// View customer accounts
function viewCustomerAccounts(customerId) {
    currentCustomerId = customerId;
    showSection('accounts');
    loadCustomerAccounts();
}

// Load customer select dropdown
async function loadCustomerSelect() {
    try {
        const response = await fetch('/api/customers');
        const customerList = await response.json();
        
        const select = document.getElementById('customer-select');
        select.innerHTML = '<option value="">Select a customer...</option>' +
            customerList.map(customer => 
                `<option value="${customer.customer_id}">${customer.customer_id} - ${customer.first_name} ${customer.last_name}</option>`
            ).join('');
    } catch (error) {
        console.error('Error loading customers:', error);
    }
}

// Load accounts for selected customer
async function loadCustomerAccounts() {
    const customerId = currentCustomerId || document.getElementById('customer-select').value;
    
    if (!customerId) {
        document.getElementById('accounts-table').innerHTML = 
            '<tr><td colspan="7" class="loading">Select a customer to view accounts</td></tr>';
        return;
    }
    
    try {
        const response = await fetch(`/api/customers/${customerId}/accounts`);
        accounts = await response.json();
        displayAccounts(accounts);
    } catch (error) {
        console.error('Error loading accounts:', error);
        showError('Failed to load accounts');
    }
}

// Display accounts in table
function displayAccounts(accountList) {
    const tbody = document.getElementById('accounts-table');
    
    if (accountList.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7" class="loading">No accounts found</td></tr>';
        return;
    }
    
    tbody.innerHTML = accountList.map(account => `
        <tr>
            <td>${account.account_number}</td>
            <td>${account.account_type}</td>
            <td class="amount-${account.balance >= 0 ? 'positive' : 'negative'}">$${parseFloat(account.balance).toFixed(2)}</td>
            <td><span class="status-${account.account_status.toLowerCase()}">${account.account_status}</span></td>
            <td>${(account.interest_rate * 100).toFixed(2)}%</td>
            <td>${account.credit_limit ? '$' + parseFloat(account.credit_limit).toFixed(2) : 'N/A'}</td>
            <td>
                <button class="action-btn edit" onclick="editAccount(${account.account_id})">Edit</button>
                <button class="action-btn" onclick="viewAccountTransactions(${account.account_id})">Transactions</button>
            </td>
        </tr>
    `).join('');
}

// Edit account
async function editAccount(accountId) {
    try {
        const account = accounts.find(acc => acc.account_id === accountId);
        
        // Populate form
        document.getElementById('edit-account-id').value = account.account_id;
        document.getElementById('edit-account-type').value = account.account_type;
        document.getElementById('edit-balance').value = account.balance;
        document.getElementById('edit-account-status').value = account.account_status;
        document.getElementById('edit-interest-rate').value = (account.interest_rate * 100).toFixed(4);
        document.getElementById('edit-credit-limit').value = account.credit_limit || '';
        
        // Show modal
        document.getElementById('edit-account-modal').style.display = 'block';
    } catch (error) {
        console.error('Error loading account:', error);
        showError('Failed to load account details');
    }
}

// Save account changes
document.getElementById('edit-account-form').addEventListener('submit', async function(e) {
    e.preventDefault();
    
    const accountId = document.getElementById('edit-account-id').value;
    const formData = {
        account_type: document.getElementById('edit-account-type').value,
        balance: parseFloat(document.getElementById('edit-balance').value),
        account_status: document.getElementById('edit-account-status').value,
        interest_rate: parseFloat(document.getElementById('edit-interest-rate').value) / 100,
        credit_limit: document.getElementById('edit-credit-limit').value ? 
            parseFloat(document.getElementById('edit-credit-limit').value) : null
    };
    
    try {
        const response = await fetch(`/api/accounts/${accountId}`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(formData)
        });
        
        if (response.ok) {
            showSuccess('Account updated successfully');
            closeModal('edit-account-modal');
            loadCustomerAccounts();
        } else {
            const error = await response.json();
            showError(error.error || 'Failed to update account');
        }
    } catch (error) {
        console.error('Error updating account:', error);
        showError('Failed to update account');
    }
});

// View account transactions
function viewAccountTransactions(accountId) {
    currentAccountId = accountId;
    showSection('transactions');
    loadAccountTransactions();
}

// Load account select dropdown
async function loadAccountSelect() {
    try {
        const response = await fetch('/api/customers');
        const customerList = await response.json();
        
        const select = document.getElementById('account-select');
        select.innerHTML = '<option value="">Select an account...</option>';
        
        // Load accounts for each customer
        for (const customer of customerList) {
            const accountsResponse = await fetch(`/api/customers/${customer.customer_id}/accounts`);
            const customerAccounts = await accountsResponse.json();
            
            customerAccounts.forEach(account => {
                const option = document.createElement('option');
                option.value = account.account_id;
                option.textContent = `${account.account_number} - ${customer.first_name} ${customer.last_name} (${account.account_type})`;
                select.appendChild(option);
            });
        }
    } catch (error) {
        console.error('Error loading accounts:', error);
    }
}

// Load transactions for selected account
async function loadAccountTransactions() {
    const accountId = currentAccountId || document.getElementById('account-select').value;
    
    if (!accountId) {
        document.getElementById('transactions-table').innerHTML = 
            '<tr><td colspan="6" class="loading">Select an account to view transactions</td></tr>';
        return;
    }
    
    try {
        const response = await fetch(`/api/accounts/${accountId}/transactions`);
        transactions = await response.json();
        displayTransactions(transactions);
        
        // Show add transaction button
        showAddTransactionButton(accountId);
    } catch (error) {
        console.error('Error loading transactions:', error);
        showError('Failed to load transactions');
    }
}

// Display transactions in table
function displayTransactions(transactionList) {
    const tbody = document.getElementById('transactions-table');
    
    if (transactionList.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" class="loading">No transactions found</td></tr>';
        return;
    }
    
    tbody.innerHTML = transactionList.map(transaction => `
        <tr>
            <td>${new Date(transaction.transaction_date).toLocaleDateString()}</td>
            <td>${transaction.transaction_type}</td>
            <td class="amount-${transaction.amount >= 0 ? 'positive' : 'negative'}">$${parseFloat(transaction.amount).toFixed(2)}</td>
            <td>${transaction.description || 'N/A'}</td>
            <td>${transaction.reference_number || 'N/A'}</td>
            <td><span class="status-${transaction.status.toLowerCase()}">${transaction.status}</span></td>
        </tr>
    `).join('');
}

// Show add transaction button
function showAddTransactionButton(accountId) {
    const sectionHeader = document.querySelector('#transactions-section .section-header');
    
    // Remove existing button if any
    const existingBtn = sectionHeader.querySelector('.add-transaction-btn');
    if (existingBtn) {
        existingBtn.remove();
    }
    
    // Add new button
    const addBtn = document.createElement('button');
    addBtn.className = 'action-btn add add-transaction-btn';
    addBtn.textContent = 'Add Transaction';
    addBtn.onclick = () => addTransaction(accountId);
    sectionHeader.appendChild(addBtn);
}

// Add transaction
function addTransaction(accountId) {
    document.getElementById('add-transaction-account-id').value = accountId;
    document.getElementById('add-transaction-modal').style.display = 'block';
}

// Save new transaction
document.getElementById('add-transaction-form').addEventListener('submit', async function(e) {
    e.preventDefault();
    
    const accountId = document.getElementById('add-transaction-account-id').value;
    const formData = {
        transaction_type: document.getElementById('add-transaction-type').value,
        amount: parseFloat(document.getElementById('add-transaction-amount').value),
        description: document.getElementById('add-transaction-description').value,
        reference_number: document.getElementById('add-transaction-reference').value || 
            'TXN-' + Math.floor(Math.random() * 1000000)
    };
    
    try {
        const response = await fetch(`/api/accounts/${accountId}/transactions`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(formData)
        });
        
        if (response.ok) {
            showSuccess('Transaction added successfully');
            closeModal('add-transaction-modal');
            loadAccountTransactions();
        } else {
            const error = await response.json();
            showError(error.error || 'Failed to add transaction');
        }
    } catch (error) {
        console.error('Error adding transaction:', error);
        showError('Failed to add transaction');
    }
});

// Modal functions
function closeModal(modalId) {
    document.getElementById(modalId).style.display = 'none';
}

// Close modals when clicking outside
window.onclick = function(event) {
    const modals = document.querySelectorAll('.modal');
    modals.forEach(modal => {
        if (event.target === modal) {
            modal.style.display = 'none';
        }
    });
}

// Refresh data
function refreshData() {
    const activeSection = document.querySelector('.section.active');
    if (activeSection.id === 'customers-section') {
        loadCustomers();
    } else if (activeSection.id === 'accounts-section') {
        loadCustomerAccounts();
    } else if (activeSection.id === 'transactions-section') {
        loadAccountTransactions();
    }
    showSuccess('Data refreshed');
}

// Utility functions
function showSuccess(message) {
    showNotification(message, 'success');
}

function showError(message) {
    showNotification(message, 'error');
}

function showNotification(message, type) {
    // Create notification element
    const notification = document.createElement('div');
    notification.className = `notification ${type}`;
    notification.textContent = message;
    notification.style.cssText = `
        position: fixed;
        top: 20px;
        right: 20px;
        padding: 15px 20px;
        background: ${type === 'success' ? '#27ae60' : '#e74c3c'};
        color: white;
        border-radius: 5px;
        font-family: 'Courier New', monospace;
        font-weight: bold;
        z-index: 10000;
        box-shadow: 0 2px 10px rgba(0,0,0,0.3);
        animation: slideIn 0.3s ease;
    `;
    
    document.body.appendChild(notification);
    
    // Remove after 3 seconds
    setTimeout(() => {
        notification.style.animation = 'slideOut 0.3s ease';
        setTimeout(() => {
            if (notification.parentNode) {
                notification.parentNode.removeChild(notification);
            }
        }, 300);
    }, 3000);
}

// Add CSS for notifications
const style = document.createElement('style');
style.textContent = `
    @keyframes slideIn {
        from { transform: translateX(100%); opacity: 0; }
        to { transform: translateX(0); opacity: 1; }
    }
    @keyframes slideOut {
        from { transform: translateX(0); opacity: 1; }
        to { transform: translateX(100%); opacity: 0; }
    }
`;
document.head.appendChild(style);

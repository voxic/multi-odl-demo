// Global state
let currentCustomer = null;
let isLoading = false;

// DOM elements
const loading = document.getElementById('loading');
const error = document.getElementById('error');
const errorMessage = document.getElementById('errorMessage');
const customerProfile = document.getElementById('customerProfile');
const totalCustomers = document.getElementById('totalCustomers');
const systemStatus = document.getElementById('systemStatus');
const statusIndicator = document.getElementById('statusIndicator');

// Initialize the app
document.addEventListener('DOMContentLoaded', function() {
    loadSystemStatus();
    loadRandomCustomer();
    
    // Add event listener for Enter key in search input
    const customerIdInput = document.getElementById('customerIdInput');
    customerIdInput.addEventListener('keypress', function(e) {
        if (e.key === 'Enter') {
            searchCustomerById();
        }
    });
});

// Load system status
async function loadSystemStatus() {
    try {
        const response = await fetch('/api/health');
        const data = await response.json();
        
        systemStatus.textContent = data.status === 'healthy' ? 'Online' : 'Offline';
        systemStatus.className = `stat-value ${data.status === 'healthy' ? 'online' : 'offline'}`;
        
        // Update status indicator
        const statusDot = statusIndicator.querySelector('.status-dot');
        const statusText = statusIndicator.querySelector('span');
        
        if (data.status === 'healthy') {
            statusDot.style.background = '#48bb78';
            statusText.textContent = 'Live';
        } else {
            statusDot.style.background = '#f56565';
            statusText.textContent = 'Offline';
        }
        
        // Set a placeholder for total customers
        totalCustomers.textContent = '1,000+';
        
    } catch (err) {
        console.error('Failed to load system status:', err);
        systemStatus.textContent = 'Offline';
        systemStatus.className = 'stat-value offline';
        
        const statusDot = statusIndicator.querySelector('.status-dot');
        const statusText = statusIndicator.querySelector('span');
        statusDot.style.background = '#f56565';
        statusText.textContent = 'Offline';
    }
}

// Load random customer
async function loadRandomCustomer() {
    if (isLoading) return;
    
    isLoading = true;
    showLoading();
    hideError();
    hideCustomerProfile();
    
    try {
        const response = await fetch('/api/customers/random');
        const customer = await response.json();
        
        if (!response.ok) {
            throw new Error(customer.error || 'Failed to load customer');
        }
        
        currentCustomer = customer;
        displayCustomerProfile(customer);
        hideLoading();
        
    } catch (err) {
        console.error('Failed to load random customer:', err);
        showError(err.message);
        hideLoading();
    } finally {
        isLoading = false;
    }
}

// Search customer by ID
async function searchCustomerById() {
    const customerIdInput = document.getElementById('customerIdInput');
    const customerId = customerIdInput.value.trim();
    
    if (!customerId) {
        showError('Please enter a customer ID');
        return;
    }
    
    if (isLoading) return;
    
    isLoading = true;
    showLoading();
    hideError();
    hideCustomerProfile();
    
    try {
        const response = await fetch(`/api/customers/${customerId}`);
        const customer = await response.json();
        
        if (!response.ok) {
            throw new Error(customer.error || 'Customer not found');
        }
        
        currentCustomer = customer;
        displayCustomerProfile(customer);
        hideLoading();
        
        // Clear the input after successful search
        customerIdInput.value = '';
        
    } catch (err) {
        console.error('Failed to load customer by ID:', err);
        showError(err.message);
        hideLoading();
    } finally {
        isLoading = false;
    }
}

// Display customer profile
function displayCustomerProfile(customer) {
    const profileHTML = createCustomerProfileHTML(customer);
    customerProfile.innerHTML = profileHTML;
    showCustomerProfile();
}

// Create customer profile HTML
function createCustomerProfileHTML(customer) {
    const statusClass = customer.profile.status.toLowerCase();
    const lastUpdated = new Date(customer.updated_at).toLocaleString();
    
    // Format accounts
    const accountsHTML = customer.accounts.map(account => `
        <div class="account-card">
            <div class="account-type">${account.account_type}</div>
            <div class="account-balance">$${formatNumber(account.balance)}</div>
            <div class="account-currency">${account.currency}</div>
        </div>
    `).join('');
    
    // Format recent transactions
    const transactionsHTML = customer.accounts.map(account => {
        if (!account.transactions || account.transactions.length === 0) {
            return '';
        }
        
        const recentTxns = account.transactions.slice(0, 3).map(txn => `
            <div class="detail-item">
                <span class="detail-label">${txn.type} - ${txn.description}</span>
                <span class="detail-value">$${formatNumber(txn.amount)}</span>
            </div>
        `).join('');
        
        return `
            <div class="detail-section">
                <h4><i class="fas fa-credit-card"></i> Recent Transactions - ${account.account_type}</h4>
                ${recentTxns}
            </div>
        `;
    }).join('');
    
    return `
        <div class="customer-header">
            <div class="customer-info">
                <h2>${customer.profile.name || 'Unknown Customer'}</h2>
                <div class="customer-id">Customer ID: ${customer.customer_id}</div>
            </div>
            <div class="customer-status ${statusClass}">${customer.profile.status}</div>
        </div>
        
        <div class="customer-details">
            <div class="detail-section">
                <h4><i class="fas fa-user"></i> Personal Information</h4>
                <div class="detail-item">
                    <span class="detail-label">Email</span>
                    <span class="detail-value">${customer.profile.email || 'N/A'}</span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">Phone</span>
                    <span class="detail-value">${customer.profile.phone || 'N/A'}</span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">Location</span>
                    <span class="detail-value">${customer.profile.location || 'N/A'}</span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">Address</span>
                    <span class="detail-value">${customer.profile.address || 'N/A'}</span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">Postal Code</span>
                    <span class="detail-value">${customer.profile.postal_code || 'N/A'}</span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">Country</span>
                    <span class="detail-value">${customer.profile.country || 'N/A'}</span>
                </div>
            </div>
            
            <div class="detail-section">
                <h4><i class="fas fa-university"></i> Account Summary</h4>
                <div class="detail-item">
                    <span class="detail-label">Total Accounts</span>
                    <span class="detail-value">${customer.accounts.length}</span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">Total Balance</span>
                    <span class="detail-value">$${formatNumber(customer.accounts.reduce((sum, acc) => sum + (acc.balance || 0), 0))}</span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">Account Types</span>
                    <span class="detail-value">${[...new Set(customer.accounts.map(acc => acc.account_type))].join(', ')}</span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">Last Updated</span>
                    <span class="detail-value">${lastUpdated}</span>
                </div>
            </div>
        </div>
        
        <div class="accounts-section">
            <h4><i class="fas fa-wallet"></i> Account Details</h4>
            <div class="accounts-grid">
                ${accountsHTML}
            </div>
        </div>
        
        ${transactionsHTML ? `
        <div class="transactions-section">
            <h4><i class="fas fa-history"></i> Recent Activity</h4>
            ${transactionsHTML}
        </div>
        ` : ''}
    `;
}

// Show/hide loading state
function showLoading() {
    loading.style.display = 'block';
}

function hideLoading() {
    loading.style.display = 'none';
}

// Show/hide error state
function showError(message) {
    errorMessage.textContent = message;
    error.style.display = 'block';
}

function hideError() {
    error.style.display = 'none';
}

// Show/hide customer profile
function showCustomerProfile() {
    customerProfile.style.display = 'block';
}

function hideCustomerProfile() {
    customerProfile.style.display = 'none';
}

// Utility function to format numbers
function formatNumber(num) {
    if (num === null || num === undefined) return '0.00';
    return new Intl.NumberFormat('en-US', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
    }).format(num);
}

// Add CSS for status classes
const style = document.createElement('style');
style.textContent = `
    .stat-value.online {
        color: #48bb78;
    }
    
    .stat-value.offline {
        color: #f56565;
    }
    
    .transactions-section {
        margin-top: 2rem;
    }
    
    .transactions-section h4 {
        font-size: 1.125rem;
        font-weight: 600;
        color: #1e3c72;
        margin-bottom: 1rem;
        display: flex;
        align-items: center;
        gap: 0.5rem;
    }
    
    .transactions-section h4 i {
        color: #2a5298;
    }
`;
document.head.appendChild(style);

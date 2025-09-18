// Global state
let currentPage = 1;
let totalPages = 1;
let currentFilters = {
    search: '',
    status: '',
    risk: ''
};

// DOM elements
const searchInput = document.getElementById('searchInput');
const statusFilter = document.getElementById('statusFilter');
const riskFilter = document.getElementById('riskFilter');
const customerGrid = document.getElementById('customerGrid');
const loading = document.getElementById('loading');
const error = document.getElementById('error');
const errorMessage = document.getElementById('errorMessage');
const pagination = document.getElementById('pagination');
const prevBtn = document.getElementById('prevBtn');
const nextBtn = document.getElementById('nextBtn');
const pageInfo = document.getElementById('pageInfo');
const customerModal = document.getElementById('customerModal');
const modalTitle = document.getElementById('modalTitle');
const modalBody = document.getElementById('modalBody');

// Header stats elements
const totalCustomers = document.getElementById('totalCustomers');
const analyticsRecords = document.getElementById('analyticsRecords');
const systemStatus = document.getElementById('systemStatus');

// Initialize the app
document.addEventListener('DOMContentLoaded', function() {
    loadStats();
    loadCustomers();
    setupEventListeners();
});

// Event listeners
function setupEventListeners() {
    searchInput.addEventListener('input', debounce(handleSearch, 300));
    statusFilter.addEventListener('change', handleFilterChange);
    riskFilter.addEventListener('change', handleFilterChange);
    
    // Close modal when clicking outside
    customerModal.addEventListener('click', function(e) {
        if (e.target === customerModal) {
            closeModal();
        }
    });
}

// Debounce function for search
function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

// Load system stats
async function loadStats() {
    try {
        const response = await fetch('/api/stats');
        const data = await response.json();
        
        totalCustomers.textContent = data.cluster1_customers || 0;
        analyticsRecords.textContent = data.cluster2_analytics || 0;
        systemStatus.textContent = data.processing ? 'Processing' : 'Ready';
        systemStatus.className = `stat-value status ${data.processing ? 'processing' : 'ready'}`;
    } catch (err) {
        console.error('Failed to load stats:', err);
    }
}

// Load customers
async function loadCustomers() {
    showLoading();
    hideError();
    
    try {
        const params = new URLSearchParams({
            page: currentPage,
            limit: 12,
            ...currentFilters
        });
        
        const response = await fetch(`/api/customers?${params}`);
        const data = await response.json();
        
        if (!response.ok) {
            throw new Error(data.error || 'Failed to load customers');
        }
        
        displayCustomers(data.customers);
        updatePagination(data.pagination);
        hideLoading();
    } catch (err) {
        console.error('Failed to load customers:', err);
        showError(err.message);
        hideLoading();
    }
}

// Display customers in grid
function displayCustomers(customers) {
    customerGrid.innerHTML = '';
    
    if (customers.length === 0) {
        customerGrid.innerHTML = `
            <div style="grid-column: 1 / -1; text-align: center; padding: 3rem; color: white;">
                <i class="fas fa-users" style="font-size: 3rem; margin-bottom: 1rem; opacity: 0.5;"></i>
                <p>No customers found</p>
            </div>
        `;
        return;
    }
    
    customers.forEach(customer => {
        const card = createCustomerCard(customer);
        customerGrid.appendChild(card);
    });
}

// Create customer card element
function createCustomerCard(customer) {
    const card = document.createElement('div');
    card.className = 'customer-card';
    card.onclick = () => showCustomerDetails(customer.customer_id);
    
    const statusClass = customer.profile.status.toLowerCase();
    const riskClass = customer.risk_profile.default_risk.toLowerCase();
    
    card.innerHTML = `
        <div class="customer-header">
            <div>
                <div class="customer-name">${customer.profile.name || 'Unknown'}</div>
                <div class="customer-id">ID: ${customer.customer_id}</div>
            </div>
            <div class="status-badge ${statusClass}">${customer.profile.status}</div>
        </div>
        
        <div class="customer-info">
            <div class="info-item">
                <i class="fas fa-envelope"></i>
                <span>${customer.profile.email || 'N/A'}</span>
            </div>
            <div class="info-item">
                <i class="fas fa-map-marker-alt"></i>
                <span>${customer.profile.location || 'N/A'}</span>
            </div>
            <div class="info-item">
                <i class="fas fa-phone"></i>
                <span>${customer.profile.phone || 'N/A'}</span>
            </div>
        </div>
        
        <div class="financial-summary">
            <div class="financial-title">Financial Summary</div>
            <div class="financial-grid">
                <div class="financial-item">
                    <div class="financial-label">Total Balance</div>
                    <div class="financial-value">$${formatNumber(customer.financial_summary.total_balance)}</div>
                </div>
                <div class="financial-item">
                    <div class="financial-label">Accounts</div>
                    <div class="financial-value">${customer.financial_summary.total_accounts}</div>
                </div>
                <div class="financial-item">
                    <div class="financial-label">Agreements</div>
                    <div class="financial-value">${customer.financial_summary.total_agreements}</div>
                </div>
                <div class="financial-item">
                    <div class="financial-label">Monthly Txns</div>
                    <div class="financial-value">${customer.financial_summary.avg_monthly_transactions}</div>
                </div>
            </div>
        </div>
        
        <div class="risk-profile">
            <div class="risk-badge ${riskClass}">${customer.risk_profile.default_risk} Risk</div>
            <div class="risk-badge ${customer.risk_profile.credit_score_band.toLowerCase()}">${customer.risk_profile.credit_score_band}</div>
        </div>
    `;
    
    return card;
}

// Show customer details modal
async function showCustomerDetails(customerId) {
    try {
        const response = await fetch(`/api/customers/${customerId}`);
        const customer = await response.json();
        
        if (!response.ok) {
            throw new Error(customer.error || 'Failed to load customer details');
        }
        
        modalTitle.textContent = `${customer.profile.name} - Customer Details`;
        modalBody.innerHTML = createCustomerDetailsHTML(customer);
        customerModal.classList.add('show');
    } catch (err) {
        console.error('Failed to load customer details:', err);
        alert('Failed to load customer details: ' + err.message);
    }
}

// Create customer details HTML
function createCustomerDetailsHTML(customer) {
    const lastTransactionDate = customer.financial_summary.last_transaction_date 
        ? new Date(customer.financial_summary.last_transaction_date).toLocaleDateString()
        : 'N/A';
    
    return `
        <div class="detail-section">
            <h3>Profile Information</h3>
            <div class="detail-grid">
                <div class="detail-item">
                    <div class="detail-label">Full Name</div>
                    <div class="detail-value">${customer.profile.name || 'N/A'}</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Email</div>
                    <div class="detail-value">${customer.profile.email || 'N/A'}</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Phone</div>
                    <div class="detail-value">${customer.profile.phone || 'N/A'}</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Status</div>
                    <div class="detail-value">${customer.profile.status || 'N/A'}</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Location</div>
                    <div class="detail-value">${customer.profile.location || 'N/A'}</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Address</div>
                    <div class="detail-value">${customer.profile.address || 'N/A'}</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Postal Code</div>
                    <div class="detail-value">${customer.profile.postal_code || 'N/A'}</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Country</div>
                    <div class="detail-value">${customer.profile.country || 'N/A'}</div>
                </div>
            </div>
        </div>
        
        <div class="detail-section">
            <h3>Financial Summary</h3>
            <div class="detail-grid">
                <div class="detail-item">
                    <div class="detail-label">Total Balance</div>
                    <div class="detail-value">$${formatNumber(customer.financial_summary.total_balance)}</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Total Accounts</div>
                    <div class="detail-value">${customer.financial_summary.total_accounts}</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Account Types</div>
                    <div class="detail-value">${customer.financial_summary.account_types.join(', ') || 'N/A'}</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Monthly Transactions</div>
                    <div class="detail-value">${customer.financial_summary.avg_monthly_transactions}</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Last Transaction</div>
                    <div class="detail-value">${lastTransactionDate}</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Total Agreements</div>
                    <div class="detail-value">${customer.financial_summary.total_agreements}</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Active Agreements</div>
                    <div class="detail-value">${customer.financial_summary.active_agreements}</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Principal Amount</div>
                    <div class="detail-value">$${formatNumber(customer.financial_summary.total_principal_amount)}</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Current Balance</div>
                    <div class="detail-value">$${formatNumber(customer.financial_summary.total_current_balance)}</div>
                </div>
            </div>
        </div>
        
        <div class="detail-section">
            <h3>Risk Profile</h3>
            <div class="detail-grid">
                <div class="detail-item">
                    <div class="detail-label">Credit Score Band</div>
                    <div class="detail-value">${customer.risk_profile.credit_score_band}</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Default Risk</div>
                    <div class="detail-value">${customer.risk_profile.default_risk}</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Transaction Pattern</div>
                    <div class="detail-value">${customer.risk_profile.transaction_pattern}</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Agreement Risk</div>
                    <div class="detail-value">${customer.risk_profile.agreement_risk}</div>
                </div>
            </div>
        </div>
        
        <div class="detail-section">
            <h3>System Information</h3>
            <div class="detail-grid">
                <div class="detail-item">
                    <div class="detail-label">Customer ID</div>
                    <div class="detail-value">${customer.customer_id}</div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Last Updated</div>
                    <div class="detail-value">${new Date(customer.computed_at).toLocaleString()}</div>
                </div>
            </div>
        </div>
    `;
}

// Close modal
function closeModal() {
    customerModal.classList.remove('show');
}

// Handle search
function handleSearch(e) {
    currentFilters.search = e.target.value;
    currentPage = 1;
    loadCustomers();
}

// Handle filter changes
function handleFilterChange() {
    currentFilters.status = statusFilter.value;
    currentFilters.risk = riskFilter.value;
    currentPage = 1;
    loadCustomers();
}

// Change page
function changePage(direction) {
    const newPage = currentPage + direction;
    if (newPage >= 1 && newPage <= totalPages) {
        currentPage = newPage;
        loadCustomers();
    }
}

// Update pagination
function updatePagination(paginationData) {
    totalPages = paginationData.pages;
    currentPage = paginationData.page;
    
    prevBtn.disabled = currentPage <= 1;
    nextBtn.disabled = currentPage >= totalPages;
    
    pageInfo.textContent = `Page ${currentPage} of ${totalPages}`;
    
    if (totalPages > 1) {
        pagination.style.display = 'flex';
    } else {
        pagination.style.display = 'none';
    }
}

// Show/hide loading state
function showLoading() {
    loading.style.display = 'block';
    customerGrid.style.display = 'none';
    pagination.style.display = 'none';
}

function hideLoading() {
    loading.style.display = 'none';
    customerGrid.style.display = 'grid';
}

// Show/hide error state
function showError(message) {
    errorMessage.textContent = message;
    error.style.display = 'block';
    customerGrid.style.display = 'none';
    pagination.style.display = 'none';
}

function hideError() {
    error.style.display = 'none';
}

// Utility function to format numbers
function formatNumber(num) {
    if (num === null || num === undefined) return '0';
    return new Intl.NumberFormat('en-US', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
    }).format(num);
}

// Refresh data every 30 seconds
setInterval(() => {
    loadStats();
    if (!customerModal.classList.contains('show')) {
        loadCustomers();
    }
}, 30000);

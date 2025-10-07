# BankUI Landing Page

A sleek and modern banking UI landing page that displays random customer profiles from MongoDB in real-time.

## Features

- 🎨 **Modern Design**: Sleek, responsive UI with banking-themed gradients and animations
- 🔄 **Random Customer Display**: Shows a different random customer profile on each load
- 📱 **Responsive Layout**: Optimized for desktop, tablet, and mobile devices
- ⚡ **Real-time Updates**: Automatically refreshes customer data every 30 seconds
- 🏦 **Banking Theme**: Professional banking color scheme and typography
- 🔗 **Microservice Integration**: Connects to the customer profile service via REST API

## Architecture

```
┌─────────────────┐    ┌──────────────────────┐    ┌─────────────────┐
│   BankUI        │    │  Customer Profile    │    │   MongoDB       │
│   Landing       │───▶│  Service             │───▶│   Atlas         │
│   (Port 3003)   │    │  (Port 3001)         │    │   Clusters      │
└─────────────────┘    └──────────────────────┘    └─────────────────┘
```

## Technology Stack

- **Frontend**: HTML5, CSS3, JavaScript (ES6+)
- **Backend**: Node.js, Express.js
- **Styling**: Custom CSS with Inter font family
- **Icons**: Font Awesome 6.0
- **Containerization**: Docker
- **Orchestration**: Kubernetes

## Quick Start

### Local Development

1. **Prerequisites**:
   - Node.js 18+
   - Docker (optional)
   - Customer Profile Service running on port 3001

2. **Install Dependencies**:
   ```bash
   cd microservices/bankui-landing
   npm install
   ```

3. **Run Locally**:
   ```bash
   npm start
   ```

4. **Access the Application**:
   - Open http://localhost:3003 in your browser

### Docker Deployment

1. **Build the Image**:
   ```bash
   ./scripts/build-bankui-landing.sh
   ```

2. **Run with Docker**:
   ```bash
   docker run -p 3003:3003 \
     -e CUSTOMER_PROFILE_SERVICE_URL=http://host.docker.internal:3001 \
     bankui-landing:latest
   ```

### Kubernetes Deployment

1. **Deploy the Service**:
   ```bash
   kubectl apply -f k8s/microservices/bankui-landing-deployment.yaml
   kubectl apply -f k8s/loadbalancer/bankui-landing-nodeport.yaml
   ```

2. **Access via NodePort**:
   - External IP:Port 30033 (or check with `kubectl get services`)

## API Endpoints

### Health Check
- **GET** `/api/health`
- Returns service health status

### Random Customer
- **GET** `/api/customers/random`
- Returns a random customer profile from the database
- Attempts up to 10 random customer IDs to find a valid profile

### Specific Customer
- **GET** `/api/customers/:id`
- Returns customer profile for specific customer ID

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `3003` | Server port |
| `CUSTOMER_PROFILE_SERVICE_URL` | `http://customer-profile-service:3001` | Customer profile service URL |

### Customization

The UI can be customized by modifying:

- **Colors**: Update CSS custom properties in `styles.css`
- **Layout**: Modify HTML structure in `index.html`
- **Behavior**: Update JavaScript logic in `script.js`
- **API Integration**: Modify server endpoints in `server.js`

## UI Components

### Header
- BankUI logo with university icon
- "New Customer" refresh button
- Live status indicator

### Hero Section
- Welcome message
- System statistics cards
- Modern gradient background

### Customer Profile Section
- Featured customer card
- Personal information display
- Account summary
- Recent transactions
- Account details grid

### Features Section
- Four feature cards highlighting capabilities
- Icons and descriptions

### Footer
- Brand information
- Links and technology credits

## Styling Features

- **Gradient Backgrounds**: Banking-themed blue gradients
- **Glass Morphism**: Semi-transparent elements with backdrop blur
- **Smooth Animations**: Hover effects and transitions
- **Responsive Grid**: CSS Grid and Flexbox layouts
- **Modern Typography**: Inter font family with proper weights
- **Color Scheme**: Professional banking colors (#1e3c72, #2a5298)

## Error Handling

- Graceful error states with retry buttons
- Loading spinners during data fetch
- Fallback content for missing data
- Console logging for debugging

## Performance

- Optimized CSS with efficient selectors
- Minimal JavaScript bundle
- Efficient API calls with retry logic
- Responsive images and icons

## Browser Support

- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+

## Development

### File Structure
```
bankui-landing/
├── server.js              # Express server
├── package.json           # Dependencies
├── Dockerfile            # Container definition
└── public/
    ├── index.html        # Main HTML template
    ├── styles.css        # CSS styles
    └── script.js         # Frontend JavaScript
```

### Adding Features

1. **New API Endpoints**: Add routes to `server.js`
2. **UI Components**: Update HTML in `index.html`
3. **Styling**: Modify CSS in `styles.css`
4. **Behavior**: Update JavaScript in `script.js`

## Monitoring

- Health check endpoint for Kubernetes probes
- Console logging for debugging
- Error tracking and reporting
- Performance metrics

## Security

- CORS enabled for cross-origin requests
- Non-root Docker user
- Input validation and sanitization
- Secure HTTP headers

## Troubleshooting

### Common Issues

1. **Customer Profile Service Not Found**:
   - Ensure customer-profile-service is running
   - Check CUSTOMER_PROFILE_SERVICE_URL environment variable

2. **No Customers Displayed**:
   - Verify MongoDB connection in customer profile service
   - Check if customer profiles exist in the database

3. **Styling Issues**:
   - Clear browser cache
   - Check CSS file loading
   - Verify Font Awesome CDN connection

### Debug Mode

Enable debug logging by setting:
```bash
NODE_ENV=development npm start
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

MIT License - see LICENSE file for details.

# 🏦 NewLo Point (NLP) Contract System

**⚠️ Disclaimer**: This smart contract is experimental software. Please conduct thorough testing and auditing before using in production environments.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-^0.8.27-blue.svg)](https://soliditylang.org/)

## 🔍 Overview

NewLo Point is an ERC20 point token with gradual transfer control functionality. During the initial service phase, user-to-user transfers are restricted, allowing only minting from the service operator. As the service evolves and exchanges are prepared, transfers can be gradually enabled.

The NewLo Point (NLP) Contract System is a comprehensive DeFi protocol suite that provides everything from NLP token issuance and management to multi-token exchange systems.

## 📦 Contract List

### 1. 💎 NewLoPoint.sol
- **Function**: ERC20-compliant NLP token issuance and management
- **Features**: 
  - Upgradeable proxy pattern
  - Supply adjustment through admin privileges
  - Standard ERC20 functionality

### 2. 🏭 NewLoPointFactory.sol
- **Function**: Factory contract for NewLoPoint tokens
- **Features**: 
  - Creation of multiple NLP token instances
  - Unified management interface

### 3. 🔄 NLPToMultiTokenExchange.sol ⭐ **Latest Version**
- **Function**: Exchange NLP to multiple tokens (ETH, USDC, USDT)
- **Features**: 
  - **🛡️ Role-based Access Control**: Granular permission management
  - **💰 Operational Fee System**: Independent operational fee configuration and management
  - **🔗 Flexible Price Management**: Chainlink Oracle + external price data
  - **⚡ Gasless Exchange**: Free transactions using permit signatures
  - **🎯 Soneium Optimization**: Optimized for oracle-limited environments

### 4. 📊 MultiTokenDistribution.sol
- **Function**: Batch distribution system for multiple tokens
- **Features**: 
  - Efficient batch processing
  - Simultaneous distribution of multiple token types
  - Gas efficiency optimization

## 🎭 Role-Based Access Control

### 🔑 Access Control Roles

| Role | Permissions | Purpose |
|------|-------------|---------|
| **DEFAULT_ADMIN_ROLE** | Full permissions | Super admin |
| **CONFIG_MANAGER_ROLE** | Configuration management | Token settings, fee configuration |
| **PRICE_UPDATER_ROLE** | Price updates | External price data updates |
| **EMERGENCY_MANAGER_ROLE** | Emergency management | Emergency stops, fund withdrawals |
| **FEE_MANAGER_ROLE** | Fee management | Operational fee configuration and withdrawals |

## 💰 Operational Fee System

### 📊 Fee Types

1. **Exchange Fee**: Basic exchange fee
2. **Operational Fee**: Additional fee for operational revenue

### 🎯 Fee Limits

- **Maximum Exchange Fee**: 5% (500 basis points)
- **Maximum Operational Fee**: 2% (200 basis points)

## 🚀 Main Features

### 💱 Multi-Token Exchange

```solidity
// Standard exchange
exchange.exchangeNLP(TokenType.ETH, nlpAmount);

// Gasless exchange
exchange.exchangeNLPWithPermit(TokenType.ETH, nlpAmount, deadline, v, r, s, user);
```

### 🔧 Management Functions

```solidity
// Grant roles
exchange.grantRole(exchange.PRICE_UPDATER_ROLE(), updaterAddress);

// Configure operational fees
exchange.configureOperationalFee(TokenType.ETH, 50, feeRecipient, true);

// Update price data
exchange.updateExternalPrice(TokenType.ETH, 2500e18);
```

## 🛡️ Security Features

### 🔒 Key Security Measures

- **Reentrancy Protection**: Uses ReentrancyGuard
- **Access Control**: Uses OpenZeppelin AccessControl
- **Price Data Validation**: Freshness checks and validity confirmation
- **Emergency Stop**: Pausable functionality for immediate stops
- **Audited**: Comprehensive security audit completed

### 📋 Security Score

- **Overall Rating**: A-grade (Excellent)
- **Test Success Rate**: 100% (34/34 tests passed)
- **Slither Analysis**: No critical vulnerabilities

## 🔧 Technical Specifications

### 📊 Supported Blockchains

- **Soneium**: Optimized for oracle-limited environments
- **Ethereum**: Full Chainlink Oracle support
- **Other EVM-compatible chains**: Flexible configuration support

### 🎯 Price Management

- **Chainlink Oracle**: Automatic price fetching
- **External Price Data**: Manual and automatic update support
- **Batch Updates**: Efficient bulk price updates

## 📁 Directory Structure

```
newlo-point-contract/
├── src/
│   ├── NewLoPoint.sol                    # NLP Token
│   ├── NewLoPointFactory.sol            # Factory
│   ├── NLPToMultiTokenExchange.sol      # Multi-token exchange (Latest)
│   ├── MultiTokenDistribution.sol       # Distribution system
│   ├── interfaces/                      # Interfaces
│   ├── tokens/                          # Token implementations
│   └── mocks/                           # Test mocks
├── test/                                # Test files
├── script/                              # Deploy scripts
├── docs/                                # Documentation
│   ├── MULTI_TOKEN_EXCHANGE_GUIDE.md    # Complete operation guide
│   ├── SECURITY_AUDIT_REPORT.md         # Security audit report
│   └── ...
└── README.md                            # This file
```

## 🚀 Quick Start

### 1. Environment Setup

```bash
# Clone the repository
git clone <repository-url>
cd newlo-point-contract

# Install dependencies
forge install

# Run tests
forge test
```

### 2. Local Development Environment Deploy

```bash
# Set environment variables
export PRIVATE_KEY="your-private-key"

# Deploy to local environment
forge script script/DeployMultiTokenExchange.s.sol:DeployMultiTokenExchangeLocal \
  --rpc-url http://localhost:8545 \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### 3. Soneium Production Environment Deploy

```bash
# Deploy to Soneium environment
forge script script/DeployMultiTokenExchange.s.sol:DeployMultiTokenExchange \
  --rpc-url https://rpc.soneium.org \
  --private-key $PRIVATE_KEY \
  --broadcast
```

## 📚 Documentation

### 📖 Detailed Guides

- **📜[Contract Addresses](docs/CONTRACT_ADDRESS.md)**: Deployed contracts
- **[Multi-Token Exchange System Complete Guide](docs/MULTI_TOKEN_EXCHANGE_GUIDE.md)**: Comprehensive operation procedures
- **[Security Audit Report](docs/SECURITY_AUDIT_REPORT.md)**: Detailed audit results
- **[Production Operations Guide](docs/PRODUCTION_OPERATIONS_GUIDE.md)**: Operational considerations

### 🔍 Feature-Specific Guides

- **[Gasless Exchange Guide](docs/GASLESS_EXCHANGE_GUIDE.md)**: How to use permit signatures
- **[Distribution System Guide](docs/MULTI_TOKEN_DISTRIBUTION_GUIDE.md)**: Efficient distribution methods
- **[Local Development Guide](LOCAL_DEVELOPMENT_GUIDE.md)**: Development environment setup

## 🧪 Testing

### 🔬 Test Execution

```bash
# Run all tests
forge test

# Run tests with verbose output
forge test -vv

# Run specific tests
forge test --match-contract NLPToMultiTokenExchangeTest

# Check coverage
forge coverage
```

### 📊 Test Results

- **Test Success Rate**: 100% (34/34 tests passed)
- **Coverage**: High-level code coverage
- **Test Categories**: 
  - Basic functionality tests
  - Security tests
  - Error handling tests
  - Integration tests
  - Fuzz tests

## 🔄 Version History

### v0.4.0 (Latest)
- ✅ Role-based Access Control implementation
- ✅ Operational fee system addition
- ✅ Security enhancements
- ✅ 34 test items completed
- ✅ Comprehensive security audit completed

### v0.3.0
- ✅ Basic multi-token exchange functionality
- ✅ Chainlink Oracle support
- ✅ Gasless exchange functionality

### v0.1.0
- ✅ NewLo Point token
- ✅ NLP distribution functionality

## 🤝 Contributing

### 📝 Contribution Guidelines

1. Fork and create pull requests
2. Add/update tests
3. Report security vulnerabilities
4. Improve documentation

### 🐛 Bug Reports

- Report bugs via GitHub Issues
- Contact directly for security-related issues

## 📄 License

MIT License - See [LICENSE](LICENSE) for details

## 🔗 Links

- **Official Website**: [NewLo Official](https://newlo.xyz)
- **Official Quest Site**: [NewLo Quest](https://app.quest.newlo.xyz)
- **Documentation**: [Docs](docs/)

---

**NewLo Point Contract System** - Next-generation DeFi protocol suite 🚀

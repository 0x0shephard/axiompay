# AxiomPay: The Stateful Settlement Protocol for the Autonomous Agent Economy

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://getfoundry.sh/)
[![Tests](https://img.shields.io/badge/Tests-49%20Passing-brightgreen.svg)](./test/)

**AxiomPay** is a custom-built, on-chain protocol that enables autonomous AI agents to pay each other in real-time for continuous services. It combines the upfront trust of an escrow with the pay-as-you-go flexibility of streaming payments.

## 🎯 The Problem

The autonomous agent economy is bottlenecked by payments:
- Traditional payment rails (Stripe, credit cards) are too slow, expensive, and require human identity
- Stateless micropayment protocols (like x402) are inefficient for continuous services
- Existing streaming protocols lack provider-side guarantees

## 💡 The Solution

AxiomPay introduces a **Provider-Verifiable Escrow** model:

1. **Payer locks 100% of session funds upfront** in a time-based escrow contract
2. **Provider verifies funds on-chain** before starting service delivery
3. **Provider earns per-second** and can withdraw at any time
4. **Payer can cancel anytime** and get refunded for unused time

### Example Use Case

```
WriterAgent wants 30 minutes of SummarizerAgent's service at 0.001 USDC/second

1. WriterAgent locks 1.8 USDC (0.001 × 1800s) in AxiomStream contract
2. SummarizerAgent verifies the funds are locked on-chain
3. SummarizerAgent starts streaming the service
4. After 10 minutes, WriterAgent cancels
5. SummarizerAgent gets paid for 10 minutes (0.6 USDC)
6. WriterAgent gets refunded for 20 minutes (1.2 USDC)
```

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Agent Applications                      │
│         (WriterAgent, SummarizerAgent, etc.)            │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│                 AxiomPay SDK (Future)                    │
│          startSession(), endSession(), verify()         │
└─────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────┬──────────────────────────────────┐
│   AxiomStream.sol    │    ServiceRegistry.sol          │
│  (Payment Escrow)    │    (Service Discovery)          │
└──────────────────────┴──────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│           Base L2 / Optimism (Settlement)               │
│              ERC-4337 (Agent Identity)                  │
│                 USDC (Payments)                         │
└─────────────────────────────────────────────────────────┘
```

## 📦 Project Structure

```
AxiomPay/
├── src/
│   ├── AxiomStream.sol          # Core payment streaming contract
│   ├── ServiceRegistry.sol      # Service discovery registry
│   ├── interfaces/              # Contract interfaces
│   └── libraries/               # Helper libraries
├── test/
│   ├── AxiomStream.t.sol       # AxiomStream tests
│   ├── ServiceRegistry.t.sol    # ServiceRegistry tests
│   └── mocks/                   # Mock contracts for testing
├── script/
│   └── DeployAxiomPay.s.sol    # Deployment script
├── foundry.toml                 # Foundry configuration
├── DEPLOYMENT.md                # Deployment guide
└── README.md                    # This file
```

## 🚀 Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Git](https://git-scm.com/downloads)

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/AxiomPay.git
cd AxiomPay

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test

# Run tests with gas reporting
forge test --gas-report
```

## 🧪 Testing

The project includes comprehensive test coverage:

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/AxiomStream.t.sol

# Run specific test
forge test --match-test testStartStream

# Generate coverage report
forge coverage
```

**Test Results**: 49/49 tests passing ✅

## 📝 Core Contracts

### AxiomStream.sol

The main payment streaming contract with time-based escrow.

**Key Functions:**
- `startStream(provider, token, ratePerSecond, duration)` - Start a new payment stream
- `withdrawFromStream(streamId)` - Provider withdraws earned funds
- `stopStream(streamId)` - Payer cancels stream and gets refund
- `getEarned(streamId)` - View earned amount
- `setProtocolFee(newFeeBps)` - Admin: Update protocol fee

**Features:**
- ✅ 100% upfront funding guarantee
- ✅ Per-second payment accrual
- ✅ Instant provider withdrawals
- ✅ Early cancellation with automatic refunds
- ✅ Configurable protocol fees (0-1%)
- ✅ Multi-token support (any ERC-20)
- ✅ Reentrancy protection
- ✅ Gas-optimized

### ServiceRegistry.sol

On-chain "Yellow Pages" for agent services.

**Key Functions:**
- `registerService(...)` - Provider registers a service
- `updateService(...)` - Update service details
- `setServiceActiveStatus(...)` - Toggle availability
- `getProviderServices(provider)` - Query provider's services
- `getCategoryServices(category)` - Find services by category
- `setServiceVerification(...)` - Admin: Verify/curate services

**Features:**
- ✅ Service registration with metadata
- ✅ Pricing tiers (min/max duration)
- ✅ Category-based discovery
- ✅ Verification badges
- ✅ Usage tracking
- ✅ Spam prevention (registration fee)

## 💰 Economics

### Protocol Fees

- **Default**: 0.10% (10 basis points)
- **Range**: 0% - 1.00% (0-100 basis points)
- **Applied on**: Provider earnings during withdrawal
- **30-60x lower** than traditional payment processors (Stripe: 2.9% + $0.30)

### Gas Costs (Base L2)

| Operation | Gas | Cost @ 1 gwei |
|-----------|-----|---------------|
| Start Stream | ~220k | $0.0002 |
| Withdraw | ~80k | $0.00008 |
| Stop Stream | ~40k | $0.00004 |

## 🔐 Security

### Implemented Protections

- ✅ **ReentrancyGuard** on all state-changing functions
- ✅ **Access control** with Ownable pattern
- ✅ **Input validation** on all parameters
- ✅ **SafeERC20** for token transfers
- ✅ **Overflow/underflow** protection (Solidity 0.8.20+)
- ✅ **Time manipulation** resistance
- ✅ **Comprehensive test suite** (49 tests)

### Audit Status

⚠️ **Not yet audited** - Do not use in production without professional security audit

**Recommended Auditors:**
- [Trail of Bits](https://www.trailofbits.com/)
- [OpenZeppelin](https://www.openzeppelin.com/security-audits)
- [Consensys Diligence](https://consensys.net/diligence/)

## 🚢 Deployment

See [DEPLOYMENT.md](./DEPLOYMENT.md) for complete deployment instructions.

**Quick Deploy (Testnet):**

```bash
# Set environment variables
export PRIVATE_KEY=0x...
export DEPLOYER_ADDRESS=0x...
export BASE_SEPOLIA_RPC_URL=https://sepolia.base.org

# Deploy
forge script script/DeployAxiomPay.s.sol:DeployAxiomPay \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --broadcast \
    --verify
```

## 🤝 Use Cases

### 1. AI Agent Compute Rental
- **WriterAgent** pays **GPUAgent** for on-demand compute
- Per-second billing for efficient resource usage
- Instant cancellation when job completes

### 2. Real-Time Data Feeds
- **TradingAgent** subscribes to **MarketDataAgent**
- Continuous data streaming with guaranteed payment
- Pay only for data actually received

### 3. Decentralized Banking
- **CustomerAgent** pays **BankAgent** for account services
- Time-based fees for account maintenance
- Transparent, auditable payment history

### 4. IoT & DePIN
- **DeviceAgent** pays **NetworkAgent** for connectivity
- Per-second bandwidth billing
- Automated payment for machine-to-machine services

## 📊 Comparison with Alternatives

| Feature | AxiomPay | x402 (Coinbase) | Superfluid |
|---------|----------|-----------------|------------|
| **Model** | Stateful Escrow | Stateless Request | Open Stream |
| **Best For** | Continuous services | One-off tasks | Subscriptions |
| **Provider Guarantee** | ✅ 100% upfront | ❌ None | ❌ Can run dry |
| **Capital Efficiency** | ⚠️ Locked upfront | ✅ Pay-per-use | ✅ Streaming |
| **Cancellation** | ✅ Instant refund | N/A | ✅ Anytime |
| **Gas Efficiency** | ✅ High | ⚠️ Per-request | ✅ High |

## 🛣️ Roadmap

### Phase 1: Core Protocol ✅ (Current)
- [x] AxiomStream.sol contract
- [x] ServiceRegistry.sol contract
- [x] Comprehensive test suite
- [x] Deployment scripts
- [x] Documentation

### Phase 2: SDK & Tools (Q1 2026)
- [ ] Python SDK
- [ ] JavaScript/TypeScript SDK
- [ ] CLI tool for agent developers
- [ ] Example agent implementations

### Phase 3: Ecosystem (Q2 2026)
- [ ] Google AP2 integration
- [ ] LangChain plugin
- [ ] Autogen integration
- [ ] Developer grants program

### Phase 4: Advanced Features (Q3 2026)
- [ ] Multi-stream batching
- [ ] Gas abstraction (ERC-4337)
- [ ] Cross-chain support
- [ ] Analytics dashboard

## 🤔 FAQ

**Q: How is this different from Superfluid?**
A: Superfluid is capital-efficient but providers have no guarantee the stream won't run dry. AxiomPay locks 100% upfront, giving providers certainty before service delivery.

**Q: Why not just use x402?**
A: x402 is perfect for one-off requests but inefficient for continuous services. Paying per-second would require 3,600 transactions per hour. AxiomPay requires just 1 transaction to start, then providers withdraw as needed.

**Q: What about gas costs?**
A: On Base L2, a 30-minute stream costs ~$0.0002 to start. Traditional payment processing would cost $0.50+ for the same transaction.

**Q: Can I use this in production?**
A: Not yet - contracts should be professionally audited first. Current version is for testnet/development only.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Foundry](https://github.com/foundry-rs/foundry) for the development framework
- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts) for secure contract libraries
- [Base](https://base.org) for the optimal L2 infrastructure
- The autonomous agent developer community

## 📧 Contact

- **Website**: [Coming Soon]
- **Twitter**: [@AxiomPay](https://twitter.com/axiompay)
- **Discord**: [Community Discord]
- **Email**: hello@axiompay.xyz

---

**Built with ❤️ for the autonomous agent economy**

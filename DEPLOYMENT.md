# AxiomPay Deployment Guide

This guide walks you through deploying the AxiomPay protocol contracts to EVM-compatible networks.

## Prerequisites

1. **Foundry Installed**
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

2. **Environment Variables**
   Create a `.env` file in the project root:
   ```bash
   # Deployer account
   PRIVATE_KEY=0x...  # Your deployer private key
   DEPLOYER_ADDRESS=0x...  # Your deployer address

   # Optional: Custom fee configuration
   PROTOCOL_FEE_BPS=10  # Default: 0.10% (10 basis points)
   REGISTRATION_FEE=1000000000000000  # Default: 0.001 ETH in wei

   # RPC URLs
   BASE_RPC_URL=https://mainnet.base.org
   BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
   OPTIMISM_RPC_URL=https://mainnet.optimism.io
   OPTIMISM_SEPOLIA_RPC_URL=https://sepolia.optimism.io

   # Etherscan API keys for verification
   BASESCAN_API_KEY=...
   OPTIMISM_ETHERSCAN_API_KEY=...
   ```

3. **Fund Deployer Wallet**
   Ensure your deployer address has sufficient native tokens (ETH) for:
   - Gas fees (~0.05 ETH recommended)
   - Base Sepolia faucet: https://www.coinbase.com/faucets/base-ethereum-sepolia-faucet
   - Optimism Sepolia faucet: https://app.optimism.io/faucet

## Deployment Steps

### 1. Compile Contracts

```bash
forge build
```

Expected output:
```
[⠊] Compiling...
[⠒] Compiling X files with Solc 0.8.20
[⠑] Solc 0.8.20 finished in X.XXs
Compiler run successful!
```

### 2. Run Tests

```bash
forge test
```

Ensure all tests pass before deployment.

### 3. Deploy to Testnet (Base Sepolia)

```bash
source .env
forge script script/DeployAxiomPay.s.sol:DeployAxiomPay \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $BASESCAN_API_KEY \
    -vvvv
```

### 4. Deploy to Mainnet (Base)

**⚠️ CRITICAL: Double-check all parameters before mainnet deployment!**

```bash
source .env
forge script script/DeployAxiomPay.s.sol:DeployAxiomPay \
    --rpc-url $BASE_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $BASESCAN_API_KEY \
    -vvvv
```

### 5. Deploy to Optimism

```bash
# Testnet (Optimism Sepolia)
forge script script/DeployAxiomPay.s.sol:DeployAxiomPay \
    --rpc-url $OPTIMISM_SEPOLIA_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $OPTIMISM_ETHERSCAN_API_KEY \
    -vvvv

# Mainnet (Optimism)
forge script script/DeployAxiomPay.s.sol:DeployAxiomPay \
    --rpc-url $OPTIMISM_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $OPTIMISM_ETHERSCAN_API_KEY \
    -vvvv
```

## Constructor Parameters

### AxiomStream

| Parameter | Type | Description | Default | Range |
|-----------|------|-------------|---------|-------|
| `_initialOwner` | address | Contract owner (admin) | DEPLOYER_ADDRESS | Any valid address |
| `_protocolFeeBps` | uint256 | Protocol fee in basis points | 10 (0.10%) | 0-100 (0%-1%) |

### ServiceRegistry

| Parameter | Type | Description | Default | Range |
|-----------|------|-------------|---------|-------|
| `_initialOwner` | address | Contract owner (admin) | DEPLOYER_ADDRESS | Any valid address |
| `_registrationFee` | uint256 | Fee to register a service (in wei) | 0.001 ETH | Any uint256 |

## Post-Deployment Verification

### 1. Verify Contract Addresses

Check that contracts are deployed and verified on the block explorer:
- Base: https://basescan.org/address/<CONTRACT_ADDRESS>
- Optimism: https://optimistic.etherscan.io/address/<CONTRACT_ADDRESS>

### 2. Verify Contract State

```bash
# Check AxiomStream configuration
cast call <AXIOM_STREAM_ADDRESS> "owner()(address)" --rpc-url $BASE_RPC_URL
cast call <AXIOM_STREAM_ADDRESS> "protocolFeeBps()(uint256)" --rpc-url $BASE_RPC_URL

# Check ServiceRegistry configuration
cast call <SERVICE_REGISTRY_ADDRESS> "owner()(address)" --rpc-url $BASE_RPC_URL
cast call <SERVICE_REGISTRY_ADDRESS> "registrationFee()(uint256)" --rpc-url $BASE_RPC_URL
```

### 3. Test Basic Functionality

Deploy a test ERC20 token and try creating a stream:

```bash
# Deploy test USDC token (on testnet only)
forge create src/test/mocks/MockERC20.sol:MockERC20 \
    --constructor-args "USD Coin" "USDC" 1000000000000 \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY

# Approve AxiomStream to spend tokens
cast send <USDC_ADDRESS> "approve(address,uint256)" <AXIOM_STREAM_ADDRESS> 1000000 \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY

# Start a stream
cast send <AXIOM_STREAM_ADDRESS> "startStream(address,address,uint256,uint256)" \
    <PROVIDER_ADDRESS> <USDC_ADDRESS> 1000 1800 \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

## Network-Specific Considerations

### Base (Recommended)

- **Chain ID**: 8453 (Mainnet), 84532 (Sepolia)
- **Block Time**: ~2 seconds
- **Gas Costs**: Very low (~$0.01-0.10 per transaction)
- **Block Explorer**: https://basescan.org
- **Best For**: Production deployment, optimal for agent economy

### Optimism

- **Chain ID**: 10 (Mainnet), 11155420 (Sepolia)
- **Block Time**: ~2 seconds
- **Gas Costs**: Low (~$0.05-0.20 per transaction)
- **Block Explorer**: https://optimistic.etherscan.io
- **Best For**: Alternative L2 deployment

## Security Checklist

Before mainnet deployment, ensure:

- [ ] All tests pass (`forge test`)
- [ ] Contracts audited by professional security firm
- [ ] Owner address is a multisig (e.g., Gnosis Safe)
- [ ] Protocol fee is reasonable (≤ 1%)
- [ ] Registration fee prevents spam but doesn't block legitimate users
- [ ] Private key is securely stored (hardware wallet recommended)
- [ ] Deployment script tested on testnet
- [ ] Emergency pause mechanism considered (if needed)

## Gas Estimates

| Operation | Estimated Gas | Cost @ 1 gwei |
|-----------|---------------|---------------|
| Deploy AxiomStream | ~1,800,000 | ~$0.002 |
| Deploy ServiceRegistry | ~1,200,000 | ~$0.001 |
| Start Stream | ~220,000 | ~$0.0002 |
| Withdraw from Stream | ~80,000 | ~$0.00008 |
| Stop Stream | ~40,000 | ~$0.00004 |
| Register Service | ~350,000 | ~$0.0003 |

*Note: Base gas prices typically ~0.01-1 gwei*

## Troubleshooting

### "Insufficient funds" Error
- Ensure deployer wallet has enough ETH for gas
- Check RPC URL is correct
- Verify network is not congested

### "Nonce too low" Error
- Wait for previous transaction to confirm
- Or manually set nonce: `--nonce <NONCE>`

### Verification Failed
- Manually verify on block explorer
- Use constructor args encoding:
  ```bash
  cast abi-encode "constructor(address,uint256)" $DEPLOYER_ADDRESS 10
  ```

### Contract Not Appearing on Block Explorer
- Wait 1-2 minutes for indexing
- Check transaction status
- Verify correct network/RPC URL

## Support & Resources

- **Documentation**: [Link to full docs]
- **Discord**: [Community Discord]
- **GitHub Issues**: https://github.com/axiompay/contracts/issues
- **Security**: security@axiompay.xyz

## License

MIT License - see LICENSE file for details

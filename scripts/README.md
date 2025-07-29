# Bidirectional Cross-Chain Swap Verification Script

This script verifies the operation of bidirectional cross-chain swaps between Ethereum Sepolia and Sui testnet.

## Features

- **Ethereum -> Sui Swap Verification**: Asset movement from Sepolia to Sui
- **Sui -> Ethereum Swap Verification**: Asset movement from Sui to Sepolia
- **Hash Lock Feature**: Implementation of secure atomic swaps
- **Time Lock Feature**: Automatic refund upon expiration
- **Partial Fill Feature**: Efficient execution of large swaps

## Prerequisites

### Required Software
1. **Node.js** (v18 or higher)
   - Download from [Node.js Official Site](https://nodejs.org/)
   - Installation check: `node --version`

2. **Git** (for repository cloning)
   - Download from [Git Official Site](https://git-scm.com/)
   - Installation check: `git --version`

### Required Accounts and Wallets
1. **Sepolia Testnet Wallet**
   - Add Sepolia testnet to wallet like MetaMask
   - Get Sepolia ETH: [Sepolia Faucet](https://sepoliafaucet.com/)

2. **Sui Testnet Wallet**
   - Install Sui Wallet: [Sui Wallet](https://chrome.google.com/webstore/detail/sui-wallet/opcgpfmipidbgpenhmajoajpbobppdil)
   - Switch to Sui testnet
   - Get testnet SUI: [Sui Faucet](https://discord.gg/sui)

### Required Environment Variable Setup
- Configure private keys in `.env.local` file (details below)

### Contract Deployment
- Ethereum and Sui escrow contracts must be deployed

## Setup

### 1. Install Dependencies

```bash
cd scripts
npm install
```

### 2. Environment Variable Configuration

Create a `.env.local` file and set the following variables:

```env
# User wallet private keys
VITE_SEPOLIA_USER_PRIVATE_KEY=0x...
VITE_SUI_USER_PRIVETE_KEY=base64_encoded_private_key

# Resolver wallet private keys
VITE_RESOLVER_PRIVATE_KEY=0x...

# Contract addresses (update after deployment)
ETH_ESCROW_ADDRESS=0x...
SUI_ESCROW_PACKAGE_ID=0x...
SUI_USED_SECRETS_REGISTRY_ID=0x...
```

### 3. Update Contract Addresses

Update the following constants in the `scripts/verify-bidirectional-swap.ts` file with the actual deployed addresses:

```typescript
const ETH_ESCROW_ADDRESS = '0x...'; // Actual Ethereum escrow address
const SUI_ESCROW_PACKAGE_ID = '0x...'; // Actual Sui package ID
const SUI_USED_SECRETS_REGISTRY_ID = '0x...'; // Actual registry ID
```

## Usage

### 1. Initial Setup

#### 1.1 Navigate to Directory
```bash
cd scripts
```

#### 1.2 Install Dependencies
```bash
npm install
```

#### 1.3 Create Environment Variables File
```bash
# Create .env.local file
touch .env.local
```

#### 1.4 Set Environment Variables
Open the `.env.local` file and add the following content:

```env
# User wallet private keys (must be set)
VITE_SEPOLIA_USER_PRIVATE_KEY=0x1234567890abcdef...
VITE_SUI_USER_PRIVETE_KEY=base64_encoded_private_key_here

# Resolver wallet private keys (must be set)
VITE_RESOLVER_PRIVATE_KEY=0xabcdef1234567890...
```

**Important Notes**: 
- Private keys must be entered in the format starting with `0x`
- Sui private keys should be entered in base64 encoded format
- Keep these private keys secure and do not make them public

### 2. Running the Script

#### 2.1 Basic Execution (Recommended)
```bash
npm run test
```

#### 2.2 Development Mode Execution
```bash
npm run dev
```

#### 2.3 Direct Execution (Advanced)
```bash
npx tsx verify-bidirectional-swap.ts
```

### 3. Verify Execution Results

When executed successfully, the following logs will be displayed:

```
🚀 Bidirectional cross-chain swap verification started
==================================================

📊 Ethereum -> Sui swap verification
------------------------------
🔍 Starting Ethereum -> Sui swap verification...
📝 Secret generation: 0x...
🔒 Hash lock generation: 0x...
⏰ Time lock setting: 1234567890
📦 Ethereum escrow creation: 0x...
✅ Ethereum escrow fill completed
📦 Sui escrow creation: 0x...
✅ Sui escrow fill completed
✅ Ethereum -> Sui swap verification successful

📊 Sui -> Ethereum swap verification
------------------------------
🔍 Starting Sui -> Ethereum swap verification...
...
✅ Sui -> Ethereum swap verification successful

🎉 Bidirectional cross-chain swap verification completed
```

### 4. Common Errors and Solutions

#### 4.1 Environment Variable Error
```
Error: Required environment variables are not set
```
**Solution**: Verify that the `.env.local` file is properly configured

#### 4.2 Network Error
```
Error: Failed to fetch
```
**Solution**: Check internet connection and verify that the RPC URL is correct

#### 4.3 Insufficient Gas Error
```
Error: insufficient funds
```
**Solution**: Verify that the wallet has sufficient gas fees

### 5. Test Amount Verification

Current test amounts:
- **Ethereum -> Sui**: 0.00001 ETH (approximately $0.00002)
- **Sui -> Ethereum**: 0.01 SUI (approximately $0.01)

These amounts can be changed within the `verify-bidirectional-swap.ts` file.

## Verification Flow

### Ethereum -> Sui Swap

1. **Secret Generation**: Generate a 32-byte random secret
2. **Hash Lock Creation**: Generate hash lock from secret
3. **Ethereum Escrow Creation**: Create escrow on Sepolia
4. **Resolver Fill**: Resolver fills the escrow
5. **Sui Escrow Creation**: Create corresponding escrow on Sui
6. **Sui Escrow Fill**: Fill Sui escrow using the secret

### Sui -> Ethereum Swap

1. **Secret Generation**: Generate a 32-byte random secret
2. **Hash Lock Creation**: Generate hash lock from secret
3. **Sui Escrow Creation**: Create escrow on Sui
4. **Sui Escrow Fill**: Fill Sui escrow using the secret
5. **Ethereum Escrow Creation**: Create corresponding escrow on Sepolia
6. **Resolver Fill**: Resolver fills the Ethereum escrow

## Rate Settings

Current rate settings:
- **1 SUI = 0.001 ETH**
- **1 ETH = 1000 SUI**

Test amount settings:
- **Ethereum -> Sui**: 0.00001 ETH
- **Sui -> Ethereum**: 0.01 SUI

These rates can be changed in `scripts/verify-bidirectional-swap.ts`:

```typescript
const ETH_TO_SUI_RATE = 0.001; // 1 SUI = 0.001 ETH
const SUI_TO_ETH_RATE = 1000; // 1 ETH = 1000 SUI

// Test amounts
const testEthAmount = parseEther('0.00001'); // 0.00001 ETH (eth->sui)
const testSuiAmount = BigInt(10000000); // 0.01 SUI (sui->eth) (1e7)
```

## Error Handling

The script properly handles the following errors:

- **Missing Environment Variables**: When required private keys are not set
- **Network Errors**: RPC connection issues
- **Contract Errors**: Transaction execution failures
- **Validation Errors**: Invalid parameters

## Log Output

The script outputs detailed logs, allowing you to track the progress of each step:

```
🚀 Bidirectional cross-chain swap verification started
==================================================

📊 Ethereum -> Sui swap verification
------------------------------
🔍 Starting Ethereum -> Sui swap verification...
📝 Secret generation: 0x...
🔒 Hash lock generation: 0x...
⏰ Time lock setting: 1234567890
📦 Ethereum escrow creation: 0x...
✅ Ethereum escrow fill completed
📦 Sui escrow creation: 0x...
✅ Sui escrow fill completed
✅ Ethereum -> Sui swap verification successful
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Environment Variable Error
**Symptoms**: `Error: Required environment variables are not set`
**Solutions**:
- Check if `.env.local` file exists: `ls -la .env.local`
- Check file contents: `cat .env.local`
- Verify private keys are in correct format (starting with 0x)

#### 2. Network Error
**Symptoms**: `Error: Failed to fetch` or `Network error`
**Solutions**:
- Check internet connection
- Check firewall settings
- Temporarily disable VPN if using one

#### 3. Contract Error
**Symptoms**: `Error: Contract not found` or `Transaction failed`
**Solutions**:
- Verify contract is properly deployed
- Check contract address is correct
- Ensure testnet is properly configured

#### 4. Insufficient Gas
**Symptoms**: `Error: insufficient funds` or `Out of gas`
**Solutions**:
- Check Sepolia ETH balance: [Sepolia Etherscan](https://sepolia.etherscan.io/)
- Check Sui testnet SUI balance
- Get tokens from faucet if needed

#### 5. Permission Error
**Symptoms**: `Error: Permission denied` or `Access denied`
**Solutions**:
- Check file permissions: `ls -la`
- Change permissions if needed: `chmod 644 .env.local`

#### 6. Node.js Version Error
**Symptoms**: `Error: Unsupported Node.js version`
**Solutions**:
- Check Node.js version: `node --version`
- Update Node.js if needed

### Running in Debug Mode

To see detailed logs:

```bash
# Display debug information
DEBUG=* npm run test

# Or run directly
DEBUG=* npx tsx verify-bidirectional-swap.ts
```

### Checking Log Files

If errors occur, check the log files:

```bash
# Create log file and run
npm run test > log.txt 2>&1

# Check log file
cat log.txt
```

## Security Notes

- **Private Key Management**: Keep private keys secure and do not commit them to public repositories
- **Testnet Usage**: Only run on testnets, not on production environments
- **Small Amount Testing**: Start with small amounts before testing with larger amounts

## License

MIT License 
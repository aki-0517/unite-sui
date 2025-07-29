# SuiFusion+ (1inch Fusion+ integration Ethereum <> Sui)

A cross-chain atomic swap implementation between Ethereum Sepolia and Sui testnet, integrated with 1inch Fusion＋

## Overview

This project implements Hash-Time Lock Contract (HTLC) pattern for secure atomic swaps between Ethereum and Sui. The system supports partial fills by multiple resolvers and includes comprehensive security measures.

## Architecture

### Components

- **Ethereum Contract**: Solidity smart contract for Ethereum-side escrow management
- **Sui Contract**: Move smart contract for Sui-side escrow management  
- **Verification Scripts**: TypeScript scripts for cross-chain swap verification
- **Integration**: 1inch Fusion+ integration for enhanced security and efficiency

### Cross-Chain Swap Flow

```mermaid
sequenceDiagram
    participant U as User
    participant ETH as Ethereum Escrow
    participant RES2 as Resolver2
    participant RES3 as Resolver3
    participant SUI as Sui Escrow
    participant SUI_RES2 as Sui Resolver2
    participant SUI_RES3 as Sui Resolver3
    participant FUSION as 1inch Fusion+
    
    Note over U, FUSION: Phase 1: Initialization and Security Check
    
    U->>FUSION: 1. Security Check
    FUSION->>FUSION: 2. Create Fusion Order
    FUSION->>FUSION: 3. Share Order via Relayer
    FUSION->>FUSION: 4. Dutch Auction Processing
    FUSION->>FUSION: 5. Gas Price Adjustment
    
    Note over U, FUSION: Phase 2: Secret and Hash Lock Generation
    
    FUSION->>FUSION: 6. Generate Secret & Hash Lock
    Note right of FUSION: Secret: 0x...<br/>Hash Lock: keccak256(secret)<br/>Time Lock: current + 1 hour
    
    Note over U, FUSION: Phase 3: Finality Wait
    
    FUSION->>FUSION: 7. Wait for Chain Finality
    
    Note over U, FUSION: Phase 4: Ethereum Escrow Creation
    
    U->>ETH: 8. Create Ethereum Escrow
    Note right of ETH: Amount: 0.0001 ETH<br/>Hash Lock: 0x...<br/>Time Lock: timestamp + 3600<br/>Taker: user address
    
    ETH-->>U: Escrow ID: 0x...
    
    Note over U, FUSION: Phase 5: Ethereum Escrow Fill (Partial Fill by 2 Resolvers)
    
    RES2->>ETH: 9a. Fill Escrow (50%)
    Note right of RES2: Amount: 0.00005 ETH<br/>Secret: 0x...
    ETH-->>RES2: Received coins
    RES2->>U: Transfer to user address
    
    RES3->>ETH: 9b. Fill Escrow (50%)
    Note right of RES3: Amount: 0.00005 ETH<br/>Secret: 0x...
    ETH-->>RES3: Received coins
    RES3->>U: Transfer to user address
    
    Note over U, FUSION: Phase 6: Sui Escrow Creation and Fill
    
    U->>SUI: 10a. Create Sui Escrow
    Note right of SUI: Amount: 0.1 SUI<br/>Hash Lock: 0x...<br/>Time Lock: timestamp + 3600000ms
    
    SUI-->>U: Sui Escrow ID: 0x...
    
    SUI_RES2->>SUI: 10b. Fill Sui Escrow (50%)
    Note right of SUI_RES2: Amount: 0.05 SUI<br/>Secret: 0x...
    SUI-->>SUI_RES2: Received coins
    SUI_RES2->>U: Transfer to user Sui address
    
    SUI_RES3->>SUI: 10c. Fill Sui Escrow (50%)
    Note right of SUI_RES3: Amount: 0.05 SUI<br/>Secret: 0x...
    SUI-->>SUI_RES3: Received coins
    SUI_RES3->>U: Transfer to user Sui address
    
    Note over U, FUSION: Phase 7: Conditional Secret Sharing
    
    FUSION->>FUSION: 11. Conditional Secret Sharing
    Note right of FUSION: Share secret when<br/>finality is confirmed
```

## Project Structure

```
unite-sui/
├── eth-contract/          # Ethereum smart contracts
│   ├── src/
│   │   ├── core/          # Main escrow contract
│   │   ├── interfaces/    # Contract interfaces
│   │   └── utils/         # Utility contracts
│   └── test/              # Solidity tests
├── sui_contract/          # Sui smart contracts
│   ├── sources/
│   │   ├── core/          # Main escrow contract
│   │   └── utils/         # Utility modules
│   └── tests/             # Move tests
└── scripts/               # Verification and integration scripts
    ├── fusion-plus.ts     # 1inch Fusion+ integration
    └── mermaid.md         # Flow diagrams
```

## Features

- **Atomic Swaps**: Secure cross-chain token exchanges using HTLC
- **Partial Fills**: Support for multiple resolvers filling escrows
- **Time Locks**: Configurable expiration times for escrows
- **Secret Management**: Secure secret generation and verification
- **1inch Integration**: Enhanced security with Fusion+ protocol
- **Multi-Chain Support**: Ethereum Sepolia and Sui testnet

## Getting Started

### Prerequisites

- Node.js 18+
- Foundry (for Ethereum contracts)
- Sui CLI (for Sui contracts)

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd unite-sui
```

2. Install dependencies:
```bash
# Ethereum contracts
cd eth-contract
forge install

# Sui contracts
cd ../sui_contract
sui move build

# Scripts
cd ../scripts
npm install
```

### Testing

```bash
# Ethereum contracts
cd eth-contract
forge test

# Sui contracts
cd ../sui_contract
sui move test

# Verification scripts
cd ../scripts
npm test
```

## Security

- Hash-Time Lock Contract (HTLC) pattern
- Reentrancy protection
- Time-based expiration
- Secret verification
- 1inch Fusion+ security features

## License

MIT License

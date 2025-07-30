# SuiFusion+ (1inch Fusion+ integration Ethereum <> Sui)

A cross-chain atomic swap implementation between Ethereum Sepolia and Sui testnet, integrated with 1inch Fusion＋

## Overview

This project implements Hash-Time Lock Contract (HTLC) pattern for secure atomic swaps between Ethereum and Sui. The system supports partial fills by multiple resolvers and includes comprehensive security measures.

## Architecture

### Main Features

- **HTLC Atomic Swaps**
  - Assets are locked with a hashlock and timelock; funds move only if the secret is revealed, otherwise refunded after expiry.
  - Implemented in `EthereumEscrow.sol` (Solidity) and `cross_chain_escrow.move` (Move).

- **Intent-based Orders & Dutch Auction**
  - Makers create orders; resolvers compete to fill them. Dutch auction lowers rates over time for optimal execution.

- **Limit Order Protocol**
  - `LimitOrderProtocol.sol` manages orders, auctions, escrows, and resolver network.

- **Resolver Network**
  - `ResolverNetwork.sol` handles resolver registration, authorization, staking, and reputation.

- **Cross-chain Coordination**
  - Order hashes and secrets link escrows on both chains; Sui mirrors HTLC logic.

- **Partial Fill**
  - Orders can be filled in parts by multiple resolvers.

- **Recovery & Security**
  - Refunds after expiry; secret reuse is prevented; resolver penalties and reputation enforced.

---

### How it's made

#### Technical Structure

- **Solidity**: `CrossChainOrder.sol` (order/escrow integration), `EthereumEscrow.sol` (HTLC), `DutchAuction.sol` (auction), `LimitOrderProtocol.sol` (order logic), `ResolverNetwork.sol` (resolver management)
- **Move**: `cross_chain_escrow.move` (HTLC), `hash_lock.move` (hashlock), `time_lock.move` (timelock)

#### Flow Overview

1. **Order Creation**: User calls `createCrossChainOrder` with auction settings; order is registered and auction started.
2. **Escrow Setup**: HTLC escrows are created on both chains, locking assets with hashlock/timelock.
3. **Auction & Fill**: Resolvers monitor auction rates and fill orders when profitable; partial fills are tracked.
4. **Cross-chain & Secret Reveal**: Secret revealed on one chain unlocks funds on the other; verification is on-chain.
5. **Completion & Refund**: Correct secret transfers assets; after expiry, refunds are possible; resolver misbehavior is penalized.

#### Design Notes

- Off-chain relayers monitor both chains and relay secrets.
- Resolver safety: KYC/KYB, staking, reputation.
- All 1inch Fusion+ features (intent, auction, HTLC, partial fill, recovery, resolver network, security) are covered within smart contract scope.


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


## License

MIT License

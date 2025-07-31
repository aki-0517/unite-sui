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

1. **Order Creation & Auction Setup**: User calls `createCrossChainOrder` with WETH, target amount, and auction configuration. LimitOrderProtocol transfers WETH, initializes Dutch auction, and registers with ResolverNetwork.

2. **Secret Generation & Escrow Creation**: User generates secret and hash lock, then calls `createEscrowForOrder` to create HTLC escrow on Ethereum with time-locked funds.

3. **Dutch Auction & Resolver Competition**: Authorized resolvers monitor decreasing auction rates via `calculateCurrentRate`. Resolvers compete by filling orders when rates become profitable.

4. **Order Fulfillment with Partial Fills**: Resolvers call `fillLimitOrder` with the secret. EthereumEscrow verifies secrets and enables partial fills by multiple resolvers. Each fill transfers WETH proportionally.

5. **Cross-Chain Escrow Operations**: User creates corresponding Sui escrow with same hash lock. Sui resolvers use the same secret to claim SUI tokens, completing the atomic swap.

6. **Completion & Reputation Updates**: LimitOrderProtocol marks orders complete, DutchAuction ends, and ResolverNetwork updates resolver reputation based on performance.


### Cross-Chain Swap Flow

```mermaid
sequenceDiagram
    participant U as User
    participant LOP as LimitOrderProtocol
    participant DA as DutchAuction
    participant RN as ResolverNetwork
    participant ETH as EthereumEscrow
    participant RES1 as Resolver1
    participant RES2 as Resolver2
    participant SUI as Sui Escrow
    participant SUI_RES1 as Sui Resolver1
    participant SUI_RES2 as Sui Resolver2
    
    Note over U, SUI_RES2: Phase 1: Order Creation & Auction Setup
    
    U->>LOP: 1. createCrossChainOrder(sourceAmount, destAmount, auctionConfig)
    Note right of U: WETH: 0.0001 ETH<br/>Target: 0.1 SUI<br/>Auction: 5min-24h duration
    
    LOP->>LOP: 2. Transfer WETH to contract
    LOP->>DA: 3. initializeAuction(orderHash, config)
    LOP->>RN: 4. registerOrder(orderHash, amounts)
    
    LOP-->>U: Order Hash: 0x...
    
    Note over U, SUI_RES2: Phase 2: Secret Generation & Escrow Creation
    
    U->>U: 5. Generate Secret & Hash Lock
    Note right of U: Secret: 0x...<br/>Hash Lock: keccak256(secret)<br/>Time Lock: current + 1 hour
    
    U->>LOP: 6. createEscrowForOrder(orderHash, hashLock, timeLock)
    LOP->>ETH: 7. createEscrow(hashLock, timeLock, amount)
    
    ETH-->>LOP: Escrow ID: 0x...
    LOP-->>U: Escrow Created
    
    Note over U, SUI_RES2: Phase 3: Dutch Auction & Resolver Competition
    
    loop Auction Period
        RES1->>DA: 8a. calculateCurrentRate(orderHash)
        DA-->>RES1: Current Rate (decreasing over time)
        RES2->>DA: 8b. calculateCurrentRate(orderHash)
        DA-->>RES2: Current Rate (decreasing over time)
    end
    
    Note over U, SUI_RES2: Phase 4: Order Fulfillment (Partial Fills)
    
    RES1->>RN: 9a. Check authorization
    RN-->>RES1: Authorized
    RES1->>LOP: 10a. fillLimitOrder(orderHash, secret)
    LOP->>DA: Get current rate
    LOP->>ETH: fillEscrow(escrowId, amount, secret)
    ETH->>ETH: Verify secret & partial fill (50%)
    ETH-->>RES1: Transfer 0.00005 WETH
    LOP->>RN: recordOrderFill(resolver, amount, rate)
    
    RES2->>LOP: 10b. fillLimitOrder(orderHash, secret)
    LOP->>ETH: fillEscrow(escrowId, remainingAmount, secret)
    ETH->>ETH: Verify same secret & complete (50%)
    ETH-->>RES2: Transfer 0.00005 WETH
    LOP->>RN: recordOrderFill(resolver, amount, rate)
    
    Note over U, SUI_RES2: Phase 5: Cross-Chain Sui Escrow Operations
    
    U->>SUI: 11a. Create Sui Escrow
    Note right of SUI: Amount: 0.1 SUI<br/>Hash Lock: 0x...<br/>Time Lock: timestamp + 3600000ms
    
    SUI-->>U: Sui Escrow ID: 0x...
    
    SUI_RES1->>SUI: 11b. Fill Sui Escrow (50%)
    Note right of SUI_RES1: Amount: 0.05 SUI<br/>Secret: 0x... (same secret)
    SUI-->>SUI_RES1: Received coins
    SUI_RES1->>U: Transfer to user Sui address
    
    SUI_RES2->>SUI: 11c. Fill Sui Escrow (50%) 
    Note right of SUI_RES2: Amount: 0.05 SUI<br/>Secret: 0x... (same secret)
    SUI-->>SUI_RES2: Received coins
    SUI_RES2->>U: Transfer to user Sui address
    
    Note over U, SUI_RES2: Phase 6: Order Completion & Cleanup
    
    LOP->>LOP: 12. Mark order as completed
    DA->>DA: 13. Auction ended
    RN->>RN: 14. Update resolver reputation
```


## License

MIT License

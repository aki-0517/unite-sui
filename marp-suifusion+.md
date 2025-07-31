---
marp: true
title: SuiFusion+ - Cross-Chain Atomic Swap Protocol
author: SuiFusion+ Team
theme: default
paginate: true
backgroundColor: #0D1117
color: #ffffff
style: |
  section {
    background: linear-gradient(135deg, #0D1117 0%, #1a1a2e 100%);
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    padding: 40px;
    font-size: 18px;
  }
  h1 {
    color: #58a6ff;
    text-align: center;
    text-shadow: 0 2px 10px rgba(88, 166, 255, 0.3);
    font-size: 2.5em;
    margin-bottom: 0.2em;
  }
  h2 {
    color: #58a6ff;
    border-bottom: 2px solid #58a6ff;
    padding-bottom: 10px;
    font-size: 1.8em;
    margin-bottom: 0.5em;
  }
  h3 {
    font-size: 1.3em;
    margin-bottom: 0.3em;
    line-height: 1.2;
  }
  .hero {
    text-align: center;
    font-size: 1.1em;
    line-height: 1.4;
  }
  .solution {
    background: rgba(56, 211, 159, 0.1);
    border-left: 4px solid #38d39f;
    padding: 20px;
    margin: 15px 0;
    font-size: 1em;
    line-height: 1.4;
  }
  .tech-stack {
    display: flex;
    justify-content: space-around;
    align-items: flex-start;
    margin: 20px 0;
    flex-wrap: wrap;
  }
  .tech-item {
    text-align: center;
    padding: 10px;
    flex: 1;
    min-width: 200px;
  }
  .tech-item h3 {
    font-size: 1.1em;
    margin-bottom: 8px;
  }
  ul {
    font-size: 1em;
    margin: 0.5em 0;
    line-height: 1.5;
  }
  li {
    margin-bottom: 0.4em;
  }
  p {
    line-height: 1.5;
    margin: 0.5em 0;
  }
  strong {
    font-weight: 600;
  }
---

# ![w:600](./public/logo.png)

<style>
section h1 img {
  height: 200px;
  object-fit: cover;
  object-position: center center;
  margin: 0 auto;
  display: block;
}
</style>
## SuiFusion+

<div class="hero">

**A cross-chain atomic swap implementation between Ethereum and Sui, integrated with 1inch Fusion+**

*Hash-Time Lock Contract (HTLC) pattern for secure atomic swaps with competitive price discovery*

</div>

---

## 💡 Our Solution

<div class="solution">

**HTLC Atomic Swaps with Dutch Auction & Partial Fill Support**

✅ **Intent-based Orders & Dutch Auction** - Makers create orders; resolvers compete to fill them. Dutch auction lowers rates over time for optimal execution.

✅ **Limit Order Protocol** - LimitOrderProtocol.sol manages orders, auctions, escrows, and resolver network.

✅ **Resolver Network** - ResolverNetwork.sol handles resolver registration, authorization, staking, and reputation.

✅ **Cross-chain Coordination** - Order hashes and secrets link escrows on both chains; Sui mirrors HTLC logic.

✅ **Partial Fill** - Orders can be filled in parts by multiple resolvers.

</div>

**True decentralization: Assets are locked with hashlock and timelock; funds move only if the secret is revealed, otherwise refunded after expiry.**

---

## 🏗️ Architecture Overview

<div class="tech-stack">

<div class="tech-item">

### 🔐 Ethereum Contracts
- **LimitOrderProtocol.sol** - Order logic & auction integration
- **EthereumEscrow.sol** - HTLC with partial fills
- **DutchAuction.sol** - Competitive price discovery
- **ResolverNetwork.sol** - Resolver management

</div>

<div class="tech-item">

### ⚡ Sui Move Modules
- **cross_chain_escrow.move** - HTLC implementation
- **hash_lock.move** - Hashlock utilities
- **time_lock.move** - Timelock mechanisms

</div>

<div class="tech-item">

### 🔄 6-Phase Flow
1. **Order Creation & Auction Setup**
2. **Secret Generation & Escrow Creation**
3. **Dutch Auction & Resolver Competition**
4. **Order Fulfillment with Partial Fills**
5. **Cross-Chain Escrow Operations**
6. **Completion & Reputation Updates**

</div>

</div>

**Key Innovation:** Multiple resolvers can partially fill orders using the same secret, enabling competitive execution while maintaining atomic guarantees across chains.
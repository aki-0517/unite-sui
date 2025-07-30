Read file: docs/1inch-fusion-plus.txt
Read file: docs/1inch-fusion-plus.txt
Search files...
# 1inch Fusion+ Limit Order Protocol実装方針

## 現状の問題点

現在の実装は**HTLC型エスクロー**のみで、1inch Fusion+の本来の要件である**Limit Order Protocol**のデプロイ・利用が不足しています。

## 実装方針

### 1. **1inch Fusion+の本来のアーキテクチャ理解**

ドキュメントによると、1inch Fusion+は以下の構造を持ちます：

```
1inch Fusion+ = Limit Order Protocol + Dutch Auction + Resolver Network
```

**現在の実装**: HTLC Escrow → **目標**: Limit Order Protocol + HTLC Escrow

### 2. **実装すべきコンポーネント**

#### A. **Limit Order Protocolコントラクト（EVM側）**

```solidity
// 新規実装が必要
contract LimitOrderProtocol {
    struct LimitOrder {
        address maker;
        address taker;
        uint256 sourceAmount;
        uint256 destinationAmount;
        uint256 deadline;
        bytes32 orderHash;
        bool isActive;
        DutchAuctionConfig auctionConfig;
    }
    
    mapping(bytes32 => LimitOrder) public orders;
    
    function createLimitOrder(
        uint256 sourceAmount,
        uint256 destinationAmount,
        uint256 deadline,
        DutchAuctionConfig calldata auctionConfig
    ) external returns (bytes32 orderHash);
    
    function fillLimitOrder(
        bytes32 orderHash,
        bytes32 secret
    ) external;
}
```

#### B. **Dutch Auction統合**

```solidity
struct DutchAuctionConfig {
    uint256 auctionStartTime;
    uint256 auctionEndTime;
    uint256 startRate;
    uint256 endRate;
    uint256 decreaseRate;
}

function calculateCurrentRate(bytes32 orderHash) public view returns (uint256);
```

#### C. **Resolver Network統合**

```solidity
interface IResolver {
    function canFillOrder(bytes32 orderHash) external view returns (bool);
    function fillOrder(bytes32 orderHash, bytes32 secret) external;
    function getSafetyDeposit() external view returns (uint256);
}
```

### 3. **実装ステップ**

#### **Phase 1: Limit Order Protocol基盤**
1. **LimitOrderProtocol.sol**の実装
2. **DutchAuction.sol**の実装
3. **ResolverRegistry.sol**の実装

#### **Phase 2: HTLC統合**
1. **既存のEthereumEscrow.sol**をLimit Order Protocolと統合
2. **CrossChainOrder.sol**の実装（Limit Order + HTLC）

<!-- #### **Phase 3: フロントエンド統合**
1. **Web UI**でLimit Order作成機能
2. **Dutch Auction可視化**
3. **Resolver選択機能** -->

### 4. **具体的な実装内容**

#### A. **LimitOrderProtocol.sol**
```solidity
contract LimitOrderProtocol {
    // 1inch Fusion+のLimit Order機能
    function createCrossChainOrder(
        uint256 sourceAmount,
        uint256 destinationAmount,
        DutchAuctionConfig calldata auctionConfig
    ) external returns (bytes32 orderHash);
    
    // HTLC統合
    function createEscrowForOrder(
        bytes32 orderHash,
        bytes32 hashLock,
        uint256 timeLock
    ) external returns (bytes32 escrowId);
}
```

#### B. **DutchAuction.sol**
```solidity
contract DutchAuction {
    function calculateCurrentRate(
        uint256 startTime,
        uint256 endTime,
        uint256 startRate,
        uint256 endRate
    ) public view returns (uint256);
    
    function isProfitableForResolver(
        bytes32 orderHash,
        uint256 resolverCost
    ) public view returns (bool);
}
```

#### C. **ResolverNetwork.sol**
```solidity
contract ResolverNetwork {
    mapping(address => bool) public authorizedResolvers;
    mapping(bytes32 => address[]) public orderResolvers;
    
    function registerResolver(address resolver) external;
    function bidOnOrder(bytes32 orderHash, uint256 bidAmount) external;
    function executeOrder(bytes32 orderHash, bytes32 secret) external;
}
```

<!-- ### 5. **Web UI統合**

#### A. **Limit Order作成画面**
```typescript
const createLimitOrder = async (amount: bigint, rate: number) => {
  // 1. Limit Order Protocolでオーダー作成
  const orderHash = await limitOrderProtocol.createOrder(amount, rate);
  
  // 2. Dutch Auction開始
  await dutchAuction.startAuction(orderHash);
  
  // 3. Resolver Networkに通知
  await resolverNetwork.notifyResolvers(orderHash);
};
```

#### B. **Dutch Auction可視化**
```typescript
const displayAuctionProgress = (orderHash: string) => {
  const currentRate = await dutchAuction.getCurrentRate(orderHash);
  const timeRemaining = await dutchAuction.getTimeRemaining(orderHash);
  
  // UIでレート変化を可視化
  updateRateDisplay(currentRate, timeRemaining);
};
``` -->

### 6. **要件満足の確認**

#### ✅ **満たされる要件**
- **Limit Order Protocolコントラクトの利用**
- **Dutch Auctionによる競争的価格発見**
- **Resolver Networkによる自動実行**
- **HTLCによる安全なクロスチェーン交換**

#### �� **既存機能との統合**
- **既存のEthereumEscrow.sol**をLimit Order Protocolと統合
- **既存のSuiコントラクト**はそのまま利用
- **既存のWeb UI**にLimit Order機能を追加


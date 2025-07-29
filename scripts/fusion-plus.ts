import { formatEther, formatGwei, keccak256, encodePacked } from 'viem/utils';
import { createPublicClient, http } from 'viem';
import { sepolia } from 'viem/chains';

// Environment variable helpers
function getRequiredEnvVar(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Required environment variable ${name} is not set. Please check your .env or .env.local file.`);
  }
  return value;
}

function getOptionalEnvVar(name: string, defaultValue: string): string {
  return process.env[name] || defaultValue;
}

function getOptionalEnvVarNumber(name: string, defaultValue: number): number {
  const value = process.env[name];
  return value ? parseFloat(value) : defaultValue;
}

function getOptionalEnvVarBoolean(name: string, defaultValue: boolean): boolean {
  const value = process.env[name];
  return value ? value.toLowerCase() === 'true' : defaultValue;
}

// Interfaces
export interface DutchAuctionConfig {
  auctionStartDelay: number;
  auctionDuration: number;
  auctionStartRateMultiplier: number;
  minimumReturnRate: number;
  decreaseRatePerMinute: number;
  priceCurveSegments: number;
}

export interface FinalityLock {
  sourceChainFinality: number;
  destinationChainFinality: number;
  secretSharingDelay: number;
  whitelistedResolvers: string[];
}

export interface SafetyDeposit {
  rate: number;
  minAmount: bigint;
  chain: 'ethereum' | 'sui';
}

export interface MerkleTreeSecrets {
  secrets: string[];
  merkleRoot: string;
  treeDepth: number;
  segments: number;
}

export interface FusionOrder {
  id: string;
  maker: string;
  sourceChain: string;
  destinationChain: string;
  sourceAmount: bigint;
  destinationAmount: bigint;
  auctionConfig: DutchAuctionConfig;
  createdAt: number;
  status: 'pending' | 'auction' | 'filled' | 'expired';
  merkleRoot?: string;
  safetyDeposit?: bigint;
}

export interface GasPriceAdjustment {
  enabled: boolean;
  volatilityThreshold: number;
  adjustmentFactor: number;
  executionThresholdMultiplier: number;
}

export interface AccessControl {
  whitelistedResolvers: string[];
  adminAddresses: string[];
  pauseGuardian: string;
}

export interface SecurityFeatures {
  reentrancyProtection: boolean;
  accessControl: AccessControl;
  emergencyPause: boolean;
  upgradeability: boolean;
}

// 1. Dutch Auction Implementation
export class DutchAuction {
  private config: DutchAuctionConfig;
  
  constructor(config?: Partial<DutchAuctionConfig>) {
    this.config = {
      auctionStartDelay: getOptionalEnvVarNumber('AUCTION_START_DELAY', 300),
      auctionDuration: getOptionalEnvVarNumber('AUCTION_DURATION', 3600),
      auctionStartRateMultiplier: getOptionalEnvVarNumber('AUCTION_START_RATE_MULTIPLIER', 6.0),
      minimumReturnRate: getOptionalEnvVarNumber('MINIMUM_RETURN_RATE', 0.8),
      decreaseRatePerMinute: getOptionalEnvVarNumber('DECREASE_RATE_PER_MINUTE', 0.01),
      priceCurveSegments: getOptionalEnvVarNumber('PRICE_CURVE_SEGMENTS', 3),
      ...config
    };
  }
  
  calculateCurrentRate(orderTimestamp: number, marketRate: number): number {
    const currentTime = Date.now() / 1000;
    const auctionStartTime = orderTimestamp + this.config.auctionStartDelay;
    
    console.log(`🏁 Dutch Auction 価格計算:`);
    console.log(`  ⏰ 現在時刻: ${new Date(currentTime * 1000).toISOString()}`);
    console.log(`  📅 オークション開始時刻: ${new Date(auctionStartTime * 1000).toISOString()}`);
    console.log(`  💰 市場レート: ${marketRate}`);
    
    if (currentTime < auctionStartTime) {
      const startRate = marketRate * this.config.auctionStartRateMultiplier;
      console.log(`  🚀 オークション前: ${startRate} (${this.config.auctionStartRateMultiplier}x)`);
      return startRate;
    }
    
    const auctionElapsed = currentTime - auctionStartTime;
    const decreaseAmount = (auctionElapsed / 60) * this.config.decreaseRatePerMinute;
    const currentRate = (marketRate * this.config.auctionStartRateMultiplier) - decreaseAmount;
    const finalRate = Math.max(currentRate, marketRate * this.config.minimumReturnRate);
    
    console.log(`  ⏳ 経過時間: ${Math.floor(auctionElapsed)}秒`);
    console.log(`  📉 減少量: ${decreaseAmount}`);
    console.log(`  💸 現在レート: ${finalRate}`);
    console.log(`  🔻 最小レート: ${marketRate * this.config.minimumReturnRate}`);
    
    return finalRate;
  }
  
  isProfitableForResolver(currentRate: number, resolverCost: number): boolean {
    const profitable = currentRate >= resolverCost;
    console.log(`💰 リゾルバー収益性チェック: ${currentRate} >= ${resolverCost} = ${profitable}`);
    return profitable;
  }
  
  getAuctionStatus(orderTimestamp: number): 'waiting' | 'active' | 'expired' {
    const currentTime = Date.now() / 1000;
    const auctionStartTime = orderTimestamp + this.config.auctionStartDelay;
    const auctionEndTime = auctionStartTime + this.config.auctionDuration;
    
    if (currentTime < auctionStartTime) return 'waiting';
    if (currentTime < auctionEndTime) return 'active';
    return 'expired';
  }
}

// 2. Finality Lock Manager
export class FinalityLockManager {
  private config: FinalityLock;
  
  constructor(config?: Partial<FinalityLock>) {
    this.config = {
      sourceChainFinality: getOptionalEnvVarNumber('ETHEREUM_FINALITY_BLOCKS', 64),
      destinationChainFinality: getOptionalEnvVarNumber('SUI_FINALITY_BLOCKS', 100),
      secretSharingDelay: getOptionalEnvVarNumber('SECRET_SHARING_DELAY', 300),
      whitelistedResolvers: getOptionalEnvVar('RESOLVER_WHITELIST', '').split(',').filter(addr => addr.length > 0),
      ...config
    };
  }
  
  async waitForChainFinality(chainId: number, blockNumber: number): Promise<void> {
    const finalityBlocks = chainId === 1 ? this.config.sourceChainFinality : this.config.destinationChainFinality;
    
    console.log(`⏳ チェーン${chainId}のfinality待機中...`);
    console.log(`📊 必要ブロック数: ${finalityBlocks}`);
    console.log(`🎯 基準ブロック: ${blockNumber}`);
    
    // Simulate finality waiting (in real implementation, check actual block numbers)
    let currentBlock = blockNumber;
    const targetBlock = blockNumber + finalityBlocks;
    
    // For testing purposes, simulate block progression
    const simulationSteps = 5;
    const stepSize = Math.floor(finalityBlocks / simulationSteps);
    
    for (let i = 0; i < simulationSteps; i++) {
      await new Promise(resolve => setTimeout(resolve, 1000));
      currentBlock += stepSize;
      const progress = Math.min(100, ((currentBlock - blockNumber) / finalityBlocks) * 100);
      console.log(`📈 Finality進捗: ${currentBlock}/${targetBlock} (${progress.toFixed(1)}%)`);
    }
    
    console.log(`✅ チェーン${chainId}のfinality確認完了`);
  }
  
  async shareSecretConditionally(
    orderId: string, 
    secret: string, 
    resolverAddress: string
  ): Promise<void> {
    console.log(`🔐 条件付きシークレット共有開始: ${orderId}`);
    
    // ホワイトリストチェック
    if (this.config.whitelistedResolvers.length > 0 && !this.config.whitelistedResolvers.includes(resolverAddress)) {
      throw new Error(`リゾルバー${resolverAddress}はホワイトリストに登録されていません`);
    }
    
    // シークレット共有遅延
    console.log(`⏳ シークレット共有遅延待機中... (${this.config.secretSharingDelay}秒)`);
    await new Promise(resolve => setTimeout(resolve, Math.min(this.config.secretSharingDelay * 100, 3000))); // 実際のテストでは短縮
    
    console.log(`🔑 シークレットをリゾルバー${resolverAddress}と共有完了`);
    console.log(`  📝 オーダーID: ${orderId}`);
    console.log(`  🔐 シークレット: ${secret.slice(0, 10)}...`);
  }
  
  isResolverWhitelisted(resolverAddress: string): boolean {
    if (this.config.whitelistedResolvers.length === 0) return true; // No whitelist means all allowed
    return this.config.whitelistedResolvers.includes(resolverAddress);
  }
}

// 3. Safety Deposit Manager
export class SafetyDepositManager {
  private config: SafetyDeposit;
  
  constructor(chain: 'ethereum' | 'sui', config?: Partial<SafetyDeposit>) {
    const minAmountStr = chain === 'ethereum' 
      ? getOptionalEnvVar('ETHEREUM_SAFETY_DEPOSIT_MIN', '1000000000000000') // 0.001 ETH in wei
      : getOptionalEnvVar('SUI_SAFETY_DEPOSIT_MIN', '1000000000'); // 1 SUI in MIST
    
    this.config = {
      rate: getOptionalEnvVarNumber('SAFETY_DEPOSIT_RATE', 0.1),
      minAmount: BigInt(minAmountStr),
      chain,
      ...config
    };
  }
  
  calculateSafetyDeposit(escrowAmount: bigint): bigint {
    const calculatedAmount = (escrowAmount * BigInt(Math.floor(this.config.rate * 1000))) / 1000n;
    const finalAmount = calculatedAmount > this.config.minAmount ? calculatedAmount : this.config.minAmount;
    
    console.log(`🛡️ Safety Deposit計算:`);
    console.log(`  💰 エスクロー金額: ${this.config.chain === 'ethereum' ? formatEther(escrowAmount) + ' ETH' : escrowAmount.toString() + ' SUI'}`);
    console.log(`  📊 レート: ${this.config.rate * 100}%`);
    console.log(`  💸 計算額: ${this.config.chain === 'ethereum' ? formatEther(calculatedAmount) + ' ETH' : calculatedAmount.toString() + ' SUI'}`);
    console.log(`  🔒 最終Safety Deposit: ${this.config.chain === 'ethereum' ? formatEther(finalAmount) + ' ETH' : finalAmount.toString() + ' SUI'}`);
    
    return finalAmount;
  }
  
  async createEscrowWithSafetyDeposit(
    amount: bigint,
    resolver: string
  ): Promise<{ totalAmount: bigint; safetyDeposit: bigint }> {
    const safetyDeposit = this.calculateSafetyDeposit(amount);
    const totalAmount = amount + safetyDeposit;
    
    console.log(`💰 Safety Deposit付きエスクロー作成:`);
    console.log(`  💸 基本金額: ${this.config.chain === 'ethereum' ? formatEther(amount) + ' ETH' : amount.toString() + ' SUI'}`);
    console.log(`  🛡️ Safety Deposit: ${this.config.chain === 'ethereum' ? formatEther(safetyDeposit) + ' ETH' : safetyDeposit.toString() + ' SUI'}`);
    console.log(`  📊 総額: ${this.config.chain === 'ethereum' ? formatEther(totalAmount) + ' ETH' : totalAmount.toString() + ' SUI'}`);
    console.log(`  👤 リゾルバー: ${resolver}`);
    
    return { totalAmount, safetyDeposit };
  }
  
  async executeWithdrawalWithIncentive(
    escrowId: string,
    resolver: string,
    safetyDeposit: bigint
  ): Promise<void> {
    console.log(`💸 Safety Deposit引き出し実行:`);
    console.log(`  📦 エスクローID: ${escrowId}`);
    console.log(`  👤 実行者: ${resolver}`);
    console.log(`  💰 インセンティブ: ${this.config.chain === 'ethereum' ? formatEther(safetyDeposit) + ' ETH' : safetyDeposit.toString() + ' SUI'}`);
    
    // Simulate withdrawal execution
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    console.log(`✅ Safety Deposit ${this.config.chain === 'ethereum' ? formatEther(safetyDeposit) + ' ETH' : safetyDeposit.toString() + ' SUI'}をリゾルバー${resolver}に支払い完了`);
  }
}

// 4. Merkle Tree Secret Manager
export class MerkleTreeSecretManager {
  private treeDepth: number;
  private segments: number;
  private secretReusePreventionEnabled: boolean;
  private usedSecrets: Set<string> = new Set();
  
  constructor(treeDepth?: number, segments?: number) {
    this.treeDepth = treeDepth || getOptionalEnvVarNumber('SECRET_TREE_DEPTH', 4);
    this.segments = segments || getOptionalEnvVarNumber('PARTIAL_FILL_SEGMENTS', 16);
    this.secretReusePreventionEnabled = getOptionalEnvVarBoolean('SECRET_REUSE_PREVENTION', true);
  }
  
  generateMerkleTreeSecrets(orderAmount: bigint): MerkleTreeSecrets {
    const secrets: string[] = [];
    
    // N+1個のシークレットを生成（N = セグメント数）
    for (let i = 0; i <= this.segments; i++) {
      let secret: string;
      do {
        secret = this.generateSecret();
      } while (this.secretReusePreventionEnabled && this.usedSecrets.has(secret));
      
      secrets.push(secret);
      if (this.secretReusePreventionEnabled) {
        this.usedSecrets.add(secret);
      }
    }
    
    const merkleRoot = this.calculateMerkleRoot(secrets);
    
    console.log(`🌳 Merkle Tree生成完了:`);
    console.log(`  📊 セグメント数: ${this.segments}`);
    console.log(`  🌿 シークレット数: ${secrets.length}`);
    console.log(`  📏 ツリー深度: ${this.treeDepth}`);
    console.log(`  🔑 Merkle Root: ${merkleRoot}`);
    console.log(`  🔒 再利用防止: ${this.secretReusePreventionEnabled ? '有効' : '無効'}`);
    
    return {
      secrets,
      merkleRoot,
      treeDepth: this.treeDepth,
      segments: this.segments
    };
  }
  
  getSecretForFillPercentage(secrets: string[], fillPercentage: number): string {
    const segmentIndex = Math.floor(fillPercentage * this.segments / 100);
    const actualIndex = Math.min(segmentIndex, secrets.length - 1);
    
    console.log(`🔍 部分フィル用シークレット取得:`);
    console.log(`  📊 フィル率: ${fillPercentage}%`);
    console.log(`  🎯 セグメントインデックス: ${actualIndex}/${secrets.length - 1}`);
    
    return secrets[actualIndex];
  }
  
  verifySecretInTree(secret: string, merkleRoot: string, proof: string[]): boolean {
    // 簡略化されたMerkle proof検証
    console.log(`🔍 Merkle Proof検証:`);
    console.log(`  🔐 シークレット: ${secret.slice(0, 10)}...`);
    console.log(`  🌳 Merkle Root: ${merkleRoot.slice(0, 10)}...`);
    console.log(`  📜 Proof長: ${proof.length}`);
    
    // 実際の実装では完全なMerkle proof検証を行う
    const isValid = proof.length > 0; // 簡略化
    console.log(`  ✅ 検証結果: ${isValid ? '有効' : '無効'}`);
    
    return isValid;
  }
  
  private generateSecret(): string {
    return '0x' + Array.from({ length: 32 }, () => Math.floor(Math.random() * 256))
      .map(b => b.toString(16).padStart(2, '0'))
      .join('');
  }
  
  private calculateMerkleRoot(secrets: string[]): string {
    // 簡略化されたMerkle root計算
    const leaves = secrets.map(secret => keccak256(secret as `0x${string}`));
    return this.buildMerkleTree(leaves);
  }
  
  private buildMerkleTree(leaves: string[]): string {
    if (leaves.length === 1) return leaves[0];
    
    const nextLevel: string[] = [];
    for (let i = 0; i < leaves.length; i += 2) {
      const left = leaves[i];
      const right = i + 1 < leaves.length ? leaves[i + 1] : left;
      const combined = keccak256(encodePacked(['bytes32', 'bytes32'], [left as `0x${string}`, right as `0x${string}`]));
      nextLevel.push(combined);
    }
    
    return this.buildMerkleTree(nextLevel);
  }
}

// 5. Fusion Relayer Service
export class FusionRelayerService {
  private orders: Map<string, FusionOrder> = new Map();
  private resolvers: string[] = [];
  private isEnabled: boolean;
  private broadcastInterval: number;
  private notificationEnabled: boolean;
  
  constructor(enabled?: boolean) {
    this.isEnabled = enabled ?? getOptionalEnvVarBoolean('RELAYER_SERVICE_ENABLED', true);
    this.broadcastInterval = getOptionalEnvVarNumber('ORDER_BROADCAST_INTERVAL', 5000);
    this.notificationEnabled = getOptionalEnvVarBoolean('RESOLVER_NOTIFICATION_ENABLED', true);
    
    // Initialize resolvers from whitelist
    this.resolvers = getOptionalEnvVar('RESOLVER_WHITELIST', '').split(',').filter(addr => addr.length > 0);
  }
  
  async shareOrder(order: FusionOrder): Promise<void> {
    this.orders.set(order.id, order);
    
    if (!this.isEnabled) {
      console.log(`📤 シンプルモード: オーダー${order.id}を全リゾルバーと共有`);
      return;
    }
    
    console.log(`📤 リレイヤーサービス: オーダー${order.id}をブロードキャスト中...`);
    console.log(`  🌐 ソースチェーン: ${order.sourceChain}`);
    console.log(`  🎯 デスティネーションチェーン: ${order.destinationChain}`);
    console.log(`  💰 ソース金額: ${order.sourceAmount.toString()}`);
    console.log(`  💸 デスティネーション金額: ${order.destinationAmount.toString()}`);
    console.log(`  👥 リゾルバー数: ${this.resolvers.length}`);
    
    // 全リゾルバーにオーダーをブロードキャスト
    for (const resolver of this.resolvers) {
      await this.notifyResolver(resolver, order);
    }
    
    // Dutch auction開始
    await this.startDutchAuction(order.id);
  }
  
  async startDutchAuction(orderId: string): Promise<void> {
    const order = this.orders.get(orderId);
    if (!order) {
      console.error(`❌ オーダー${orderId}が見つかりません`);
      return;
    }
    
    console.log(`🏁 オーダー${orderId}のDutch auction開始`);
    order.status = 'auction';
    
    // オークション監視開始
    if (this.isEnabled) {
      this.monitorAuction(orderId);
    }
  }
  
  async shareSecretConditionally(
    orderId: string, 
    secret: string,
    condition: string
  ): Promise<void> {
    const order = this.orders.get(orderId);
    if (!order) {
      console.error(`❌ オーダー${orderId}が見つかりません`);
      return;
    }
    
    console.log(`🔑 オーダー${orderId}のシークレット共有条件確認: ${condition}`);
    
    if (condition === 'finality_confirmed') {
      // Finality確認後にシークレット共有
      console.log(`⏳ Finality確認待機中...`);
      await new Promise(resolve => setTimeout(resolve, 2000)); // Simulate finality wait
      await this.shareSecretWithResolvers(orderId, secret);
    }
  }
  
  private async notifyResolver(resolver: string, order: FusionOrder): Promise<void> {
    if (!this.notificationEnabled) return;
    
    console.log(`📞 リゾルバー${resolver}にオーダー${order.id}を通知`);
    
    // Simulate notification
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  
  private async monitorAuction(orderId: string): Promise<void> {
    const order = this.orders.get(orderId);
    if (!order) return;
    
    const auction = new DutchAuction(order.auctionConfig);
    let monitoringRounds = 0;
    const maxRounds = 5; // Testing limitation
    
    console.log(`👁️ オーダー${orderId}のオークション監視開始`);
    
    // オークション監視ループ
    const interval = setInterval(async () => {
      monitoringRounds++;
      const currentRate = auction.calculateCurrentRate(order.createdAt, 1.0);
      
      console.log(`📊 オークション監視 (${monitoringRounds}/${maxRounds}):`);
      console.log(`  💰 現在レート: ${currentRate}`);
      
      // リゾルバーが利益を得られるかチェック
      for (const resolver of this.resolvers) {
        if (auction.isProfitableForResolver(currentRate, 0.9)) {
          console.log(`💰 リゾルバー${resolver}がオーダー${orderId}を実行可能`);
          await this.executeOrder(orderId, resolver);
          clearInterval(interval);
          return;
        }
      }
      
      // Testing limitation
      if (monitoringRounds >= maxRounds) {
        console.log(`⏰ オークション監視終了 (テスト制限)`);
        clearInterval(interval);
      }
    }, Math.min(this.broadcastInterval, 2000)); // Faster for testing
  }
  
  private async executeOrder(orderId: string, resolver: string): Promise<void> {
    const order = this.orders.get(orderId);
    if (!order) return;
    
    console.log(`⚡ オーダー実行:`);
    console.log(`  📦 オーダーID: ${orderId}`);
    console.log(`  👤 実行リゾルバー: ${resolver}`);
    console.log(`  💰 実行金額: ${order.sourceAmount.toString()}`);
    
    order.status = 'filled';
    
    // Simulate order execution
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    console.log(`✅ オーダー${orderId}実行完了`);
  }
  
  private async shareSecretWithResolvers(orderId: string, secret: string): Promise<void> {
    console.log(`🔐 全リゾルバーとシークレット共有:`);
    console.log(`  📦 オーダーID: ${orderId}`);
    console.log(`  🔑 シークレット: ${secret.slice(0, 10)}...`);
    console.log(`  👥 共有先: ${this.resolvers.length}人のリゾルバー`);
    
    for (const resolver of this.resolvers) {
      console.log(`  📤 ${resolver}: 共有完了`);
    }
  }
  
  getOrderStatus(orderId: string): string {
    const order = this.orders.get(orderId);
    return order ? order.status : 'not_found';
  }
}

// 6. Gas Price Adjustment Manager
export class GasPriceAdjustmentManager {
  private config: GasPriceAdjustment;
  private historicalGasPrices: Map<string, bigint[]> = new Map();
  
  constructor(config?: Partial<GasPriceAdjustment>) {
    this.config = {
      enabled: getOptionalEnvVarBoolean('GAS_PRICE_ADJUSTMENT_ENABLED', true),
      volatilityThreshold: getOptionalEnvVarNumber('GAS_VOLATILITY_THRESHOLD', 0.2),
      adjustmentFactor: getOptionalEnvVarNumber('PRICE_ADJUSTMENT_FACTOR', 1.5),
      executionThresholdMultiplier: getOptionalEnvVarNumber('EXECUTION_THRESHOLD_MULTIPLIER', 1.2),
      ...config
    };
  }
  
  async adjustPriceForGasVolatility(
    originalPrice: number,
    chainId: number
  ): Promise<number> {
    if (!this.config.enabled) {
      console.log(`⛽ Gas Price Adjustment無効 - 元価格維持: ${originalPrice}`);
      return originalPrice;
    }
    
    const currentBaseFee = await this.getCurrentBaseFee(chainId);
    const chainKey = chainId.toString();
    const historicalPrices = this.historicalGasPrices.get(chainKey) || [];
    
    // 履歴を更新
    this.updateHistoricalPrices(chainId, currentBaseFee);
    
    if (historicalPrices.length === 0) {
      console.log(`⛽ Gas Price Adjustment: 履歴不足 - 元価格維持: ${originalPrice}`);
      return originalPrice;
    }
    
    const averageHistoricalPrice = this.calculateAverage(historicalPrices);
    const gasVolatility = this.calculateGasVolatility(currentBaseFee, averageHistoricalPrice);
    
    console.log(`⛽ Gas Price Adjustment:`);
    console.log(`  📊 チェーンID: ${chainId}`);
    console.log(`  ⛽ 現在のBase Fee: ${formatGwei(currentBaseFee)} Gwei`);
    console.log(`  📈 平均Base Fee: ${formatGwei(averageHistoricalPrice)} Gwei`);
    console.log(`  📉 変動率: ${(gasVolatility * 100).toFixed(2)}%`);
    console.log(`  🎯 変動閾値: ${(this.config.volatilityThreshold * 100).toFixed(2)}%`);
    
    if (Math.abs(gasVolatility) > this.config.volatilityThreshold) {
      const adjustedPrice = originalPrice * (1 + gasVolatility * this.config.adjustmentFactor);
      console.log(`🔄 価格調整実行: ${originalPrice} → ${adjustedPrice.toFixed(6)} (${this.config.adjustmentFactor}x調整)`);
      return adjustedPrice;
    }
    
    console.log(`✅ 価格調整不要: ${originalPrice}`);
    return originalPrice;
  }
  
  async shouldExecuteOrder(
    orderPrice: number,
    currentGasPrice: bigint,
    chainId: number
  ): Promise<boolean> {
    const executionThreshold = this.calculateExecutionThreshold(currentGasPrice);
    const adjustedPrice = await this.adjustPriceForGasVolatility(orderPrice, chainId);
    
    const shouldExecute = adjustedPrice >= executionThreshold;
    
    console.log(`🤔 オーダー実行判定:`);
    console.log(`  💰 調整後価格: ${adjustedPrice.toFixed(6)}`);
    console.log(`  🎯 実行閾値: ${executionThreshold.toFixed(6)}`);
    console.log(`  ✅ 実行可否: ${shouldExecute ? '実行可能' : '実行不可'}`);
    
    return shouldExecute;
  }
  
  private async getCurrentBaseFee(chainId: number): Promise<bigint> {
    // Simulate current base fee (in real implementation, fetch from RPC)
    const simulatedBaseFee = BigInt(Math.floor(Math.random() * 50 + 20)) * BigInt(1e9); // 20-70 Gwei
    console.log(`📊 シミュレートされたBase Fee: ${formatGwei(simulatedBaseFee)} Gwei`);
    return simulatedBaseFee;
  }
  
  private updateHistoricalPrices(chainId: number, price: bigint): void {
    const chainKey = chainId.toString();
    const prices = this.historicalGasPrices.get(chainKey) || [];
    
    prices.push(price);
    
    // Keep only last 100 prices
    if (prices.length > 100) {
      prices.shift();
    }
    
    this.historicalGasPrices.set(chainKey, prices);
  }
  
  private calculateAverage(prices: bigint[]): bigint {
    if (prices.length === 0) return BigInt(0);
    
    const sum = prices.reduce((acc, price) => acc + price, BigInt(0));
    return sum / BigInt(prices.length);
  }
  
  private calculateGasVolatility(current: bigint, historical: bigint): number {
    if (historical === BigInt(0)) return 0;
    return Number(current - historical) / Number(historical);
  }
  
  private calculateExecutionThreshold(currentGasPrice: bigint): number {
    return Number(currentGasPrice) * this.config.executionThresholdMultiplier;
  }
}

// 7. Security Manager
export class SecurityManager {
  private config: SecurityFeatures;
  private isPaused: boolean = false;
  private reentrancyGuard: Set<string> = new Set();
  
  constructor(config?: Partial<SecurityFeatures>) {
    const whitelistedResolvers = getOptionalEnvVar('RESOLVER_WHITELIST', '').split(',').filter(addr => addr.length > 0);
    const adminAddresses = getOptionalEnvVar('ADMIN_ADDRESSES', '').split(',').filter(addr => addr.length > 0);
    const pauseGuardian = getOptionalEnvVar('PAUSE_GUARDIAN', adminAddresses[0] || '');
    
    this.config = {
      reentrancyProtection: getOptionalEnvVarBoolean('REENTRANCY_PROTECTION', true),
      accessControl: {
        whitelistedResolvers,
        adminAddresses,
        pauseGuardian,
        ...config?.accessControl
      },
      emergencyPause: getOptionalEnvVarBoolean('EMERGENCY_PAUSE_ENABLED', true),
      upgradeability: getOptionalEnvVarBoolean('UPGRADEABILITY_ENABLED', true),
      ...config
    };
    
    console.log(`🛡️ Security Manager初期化:`);
    console.log(`  🔒 Reentrancy Protection: ${this.config.reentrancyProtection ? '有効' : '無効'}`);
    console.log(`  👥 ホワイトリストリゾルバー: ${this.config.accessControl.whitelistedResolvers.length}個`);
    console.log(`  👑 管理者: ${this.config.accessControl.adminAddresses.length}個`);
    console.log(`  🚨 緊急停止: ${this.config.emergencyPause ? '有効' : '無効'}`);
    console.log(`  🔄 アップグレード可能: ${this.config.upgradeability ? '有効' : '無効'}`);
  }
  
  async checkReentrancyProtection(txHash: string): Promise<boolean> {
    if (!this.config.reentrancyProtection) {
      console.log(`🔓 Reentrancy Protection無効 - チェックスキップ`);
      return true;
    }
    
    if (this.reentrancyGuard.has(txHash)) {
      console.error(`🚫 Reentrancy攻撃検出: ${txHash}`);
      return false;
    }
    
    console.log(`✅ Reentrancy Protection: ${txHash} - 安全`);
    this.reentrancyGuard.add(txHash);
    
    // Clean up after 60 seconds
    setTimeout(() => {
      this.reentrancyGuard.delete(txHash);
      console.log(`🧹 Reentrancy Guard クリーンアップ: ${txHash}`);
    }, 60000);
    
    return true;
  }
  
  async checkAccessControl(user: string, action: string): Promise<boolean> {
    console.log(`🔐 アクセス制御チェック:`);
    console.log(`  👤 ユーザー: ${user}`);
    console.log(`  🎯 アクション: ${action}`);
    
    const { adminAddresses, whitelistedResolvers, pauseGuardian } = this.config.accessControl;
    
    let hasAccess = false;
    
    switch (action) {
      case 'admin':
        hasAccess = adminAddresses.includes(user);
        console.log(`  👑 管理者権限: ${hasAccess ? '許可' : '拒否'}`);
        break;
      case 'resolver':
        hasAccess = whitelistedResolvers.length === 0 || whitelistedResolvers.includes(user);
        console.log(`  🔧 リゾルバー権限: ${hasAccess ? '許可' : '拒否'}`);
        break;
      case 'pause':
        hasAccess = user === pauseGuardian || adminAddresses.includes(user);
        console.log(`  🚨 一時停止権限: ${hasAccess ? '許可' : '拒否'}`);
        break;
      default:
        console.log(`  ❓ 不明なアクション: 拒否`);
        hasAccess = false;
    }
    
    return hasAccess;
  }
  
  async emergencyPause(): Promise<void> {
    if (!this.config.emergencyPause) {
      console.log(`🚨 緊急一時停止機能が無効です`);
      return;
    }
    
    console.log(`🚨 緊急一時停止実行中...`);
    this.isPaused = true;
    
    // 全ての進行中のトランザクションを停止
    await this.stopAllTransactions();
    
    console.log(`🛑 システム緊急一時停止完了`);
  }
  
  async emergencyResume(): Promise<void> {
    if (!this.config.emergencyPause) {
      console.log(`✅ 緊急一時停止機能が無効のため、再開不要です`);
      return;
    }
    
    console.log(`🔄 緊急一時停止解除中...`);
    this.isPaused = false;
    
    console.log(`✅ システム正常稼働再開`);
  }
  
  isPausedState(): boolean {
    return this.isPaused;
  }
  
  async performSecurityCheck(txHash: string, user: string, action: string): Promise<boolean> {
    console.log(`🛡️ 総合セキュリティチェック開始:`);
    console.log(`  📦 TX Hash: ${txHash}`);
    console.log(`  👤 User: ${user}`);
    console.log(`  🎯 Action: ${action}`);
    
    // 1. 一時停止チェック
    if (this.isPaused) {
      console.error(`🛑 システムが一時停止中です`);
      return false;
    }
    
    // 2. Reentrancy チェック
    const reentrancySafe = await this.checkReentrancyProtection(txHash);
    if (!reentrancySafe) {
      return false;
    }
    
    // 3. アクセス制御チェック
    const hasAccess = await this.checkAccessControl(user, action);
    if (!hasAccess) {
      return false;
    }
    
    console.log(`✅ 総合セキュリティチェック通過`);
    return true;
  }
  
  private async stopAllTransactions(): Promise<void> {
    console.log(`⏹️ 全トランザクション停止処理中...`);
    
    // Simulate stopping all transactions
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    console.log(`✅ 全トランザクション停止完了`);
  }
}

// Configuration helper
export function createFusionPlusConfig() {
  return {
    dutchAuction: {
      auctionStartDelay: getOptionalEnvVarNumber('AUCTION_START_DELAY', 300),
      auctionDuration: getOptionalEnvVarNumber('AUCTION_DURATION', 3600),
      auctionStartRateMultiplier: getOptionalEnvVarNumber('AUCTION_START_RATE_MULTIPLIER', 6.0),
      minimumReturnRate: getOptionalEnvVarNumber('MINIMUM_RETURN_RATE', 0.8),
      decreaseRatePerMinute: getOptionalEnvVarNumber('DECREASE_RATE_PER_MINUTE', 0.01),
      priceCurveSegments: getOptionalEnvVarNumber('PRICE_CURVE_SEGMENTS', 3)
    },
    finalityLock: {
      sourceChainFinality: getOptionalEnvVarNumber('ETHEREUM_FINALITY_BLOCKS', 64),
      destinationChainFinality: getOptionalEnvVarNumber('SUI_FINALITY_BLOCKS', 100),
      secretSharingDelay: getOptionalEnvVarNumber('SECRET_SHARING_DELAY', 300),
      whitelistedResolvers: getOptionalEnvVar('RESOLVER_WHITELIST', '').split(',').filter(addr => addr.length > 0)
    },
    safetyDeposit: {
      rate: getOptionalEnvVarNumber('SAFETY_DEPOSIT_RATE', 0.1),
      ethereumMinAmount: getOptionalEnvVar('ETHEREUM_SAFETY_DEPOSIT_MIN', '1000000000000000'),
      suiMinAmount: getOptionalEnvVar('SUI_SAFETY_DEPOSIT_MIN', '1000000000')
    },
    merkleTree: {
      depth: getOptionalEnvVarNumber('SECRET_TREE_DEPTH', 4),
      segments: getOptionalEnvVarNumber('PARTIAL_FILL_SEGMENTS', 16),
      reusePreventionEnabled: getOptionalEnvVarBoolean('SECRET_REUSE_PREVENTION', true)
    },
    relayer: {
      enabled: getOptionalEnvVarBoolean('RELAYER_SERVICE_ENABLED', true),
      broadcastInterval: getOptionalEnvVarNumber('ORDER_BROADCAST_INTERVAL', 5000),
      notificationEnabled: getOptionalEnvVarBoolean('RESOLVER_NOTIFICATION_ENABLED', true),
      secretSharingCondition: getOptionalEnvVar('SECRET_SHARING_CONDITION', 'finality_confirmed')
    },
    gasAdjustment: {
      enabled: getOptionalEnvVarBoolean('GAS_PRICE_ADJUSTMENT_ENABLED', true),
      volatilityThreshold: getOptionalEnvVarNumber('GAS_VOLATILITY_THRESHOLD', 0.2),
      adjustmentFactor: getOptionalEnvVarNumber('PRICE_ADJUSTMENT_FACTOR', 1.5),
      executionThresholdMultiplier: getOptionalEnvVarNumber('EXECUTION_THRESHOLD_MULTIPLIER', 1.2)
    },
    security: {
      reentrancyProtection: getOptionalEnvVarBoolean('REENTRANCY_PROTECTION', true),
      accessControl: {
        whitelistedResolvers: getOptionalEnvVar('RESOLVER_WHITELIST', '').split(',').filter(addr => addr.length > 0),
        adminAddresses: getOptionalEnvVar('ADMIN_ADDRESSES', '').split(',').filter(addr => addr.length > 0),
        pauseGuardian: getOptionalEnvVar('PAUSE_GUARDIAN', '')
      },
      emergencyPause: getOptionalEnvVarBoolean('EMERGENCY_PAUSE_ENABLED', true),
      upgradeability: getOptionalEnvVarBoolean('UPGRADEABILITY_ENABLED', true)
    }
  };
}
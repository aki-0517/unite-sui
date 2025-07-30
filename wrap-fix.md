# ETH → WETH ラップ対応修正ガイド

## 概要

現在のクロスチェーンswap実装はETHを直接扱っているため、標準的なWETH（Wrapped ETH）対応に修正する必要があります。

## 問題点

### 現在の実装の問題
1. **ETHを直接送金**: `value: amount`でETHを直接送金
2. **標準に準拠していない**: ほとんどのDEXはWETHを使用
3. **互換性の問題**: 他のプロトコルとの統合が困難

### 正しい実装
1. **ETH → WETH**: ユーザーがETHをWETHにラップ
2. **WETH承認**: エスクローコントラクトにWETH使用を承認
3. **WETH送金**: エスクローにWETHを転送
4. **WETH → ETH**: 受信時にWETHをアンラップ

## 1. コントラクト修正

### 1.1 インターフェース修正 (`eth-contract/src/interfaces/IEthereumEscrow.sol`)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IEthereumEscrow {
    // 既存のイベント...
    
    // 新しいイベント（WETH対応）
    event EscrowCreatedWithWeth(
        bytes32 indexed escrowId,
        address indexed maker,
        address indexed taker,
        uint256 amount,
        bytes32 hashLock,
        uint256 timeLock,
        string suiOrderHash,
        bool isWeth
    );
    
    // 既存のエラー...
    
    // 新しいエラー
    error InvalidWethAmount();
    error WethTransferFailed();
    error InsufficientWethAllowance();
    
    // 既存の関数...
    
    // 新しい関数（WETH対応）
    function createEscrowWithWeth(
        bytes32 hashLock,
        uint256 timeLock,
        address payable taker,
        string calldata suiOrderHash,
        uint256 wethAmount
    ) external returns (bytes32 escrowId);
    
    function fillEscrowWithWeth(
        bytes32 escrowId,
        uint256 amount,
        bytes32 secret
    ) external;
    
    // 新しいビュー関数
    function getEscrowWithWethInfo(bytes32 escrowId) external view returns (
        address maker,
        address taker,
        uint256 totalAmount,
        uint256 remainingAmount,
        bytes32 hashLock,
        uint256 timeLock,
        bool completed,
        bool refunded,
        uint256 createdAt,
        string memory suiOrderHash,
        bool isWeth
    );
}
```

### 1.2 メインコントラクト修正 (`eth-contract/src/core/EthereumEscrow.sol`)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IEthereumEscrow} from "../interfaces/IEthereumEscrow.sol";
import {HashLock} from "../utils/HashLock.sol";
import {TimeLock} from "../utils/TimeLock.sol";

contract EthereumEscrow is ReentrancyGuard, IEthereumEscrow {
    using SafeERC20 for IERC20;
    
    // WETHコントラクトアドレス
    IERC20 public immutable weth;
    
    // 構造体修正
    struct Escrow {
        address payable maker;
        address payable taker;
        uint256 totalAmount;
        uint256 remainingAmount;
        bytes32 hashLock;
        uint256 timeLock;
        bool completed;
        bool refunded;
        uint256 createdAt;
        string suiOrderHash;
        bytes32 secret;
        bool isWeth; // 新規追加
    }
    
    // 状態変数
    mapping(bytes32 => Escrow) public escrows;
    mapping(bytes32 => bool) public usedSecrets;
    
    // コンストラクタ修正
    constructor(address _weth) {
        weth = IERC20(_weth);
    }
    
    // 既存のcreateEscrow関数（後方互換性のため保持）
    function createEscrow(
        bytes32 hashLock,
        uint256 timeLock,
        address payable taker,
        string calldata suiOrderHash
    ) external payable nonReentrant returns (bytes32 escrowId) {
        if (msg.value == 0) revert InvalidAmount();
        if (!TimeLock.isValidTimeLock(timeLock)) revert InvalidTimeLock();
        
        escrowId = keccak256(
            abi.encodePacked(
                msg.sender,
                taker,
                msg.value,
                hashLock,
                timeLock,
                block.timestamp,
                block.number
            )
        );
        
        if (escrows[escrowId].maker != address(0)) revert EscrowAlreadyExists();
        
        escrows[escrowId] = Escrow({
            maker: payable(msg.sender),
            taker: taker,
            totalAmount: msg.value,
            remainingAmount: msg.value,
            hashLock: hashLock,
            timeLock: timeLock,
            completed: false,
            refunded: false,
            createdAt: block.timestamp,
            suiOrderHash: suiOrderHash,
            secret: bytes32(0),
            isWeth: false // ETH
        });
        
        emit EscrowCreated(
            escrowId,
            msg.sender,
            taker,
            msg.value,
            hashLock,
            timeLock,
            suiOrderHash
        );
    }
    
    // 新しいWETH対応関数
    function createEscrowWithWeth(
        bytes32 hashLock,
        uint256 timeLock,
        address payable taker,
        string calldata suiOrderHash,
        uint256 wethAmount
    ) external nonReentrant returns (bytes32 escrowId) {
        if (wethAmount == 0) revert InvalidWethAmount();
        if (!TimeLock.isValidTimeLock(timeLock)) revert InvalidTimeLock();
        
        // WETHの承認をチェック
        if (weth.allowance(msg.sender, address(this)) < wethAmount) {
            revert InsufficientWethAllowance();
        }
        
        escrowId = keccak256(
            abi.encodePacked(
                msg.sender,
                taker,
                wethAmount,
                hashLock,
                timeLock,
                block.timestamp,
                block.number
            )
        );
        
        if (escrows[escrowId].maker != address(0)) revert EscrowAlreadyExists();
        
        // WETHをコントラクトに転送
        weth.safeTransferFrom(msg.sender, address(this), wethAmount);
        
        escrows[escrowId] = Escrow({
            maker: payable(msg.sender),
            taker: taker,
            totalAmount: wethAmount,
            remainingAmount: wethAmount,
            hashLock: hashLock,
            timeLock: timeLock,
            completed: false,
            refunded: false,
            createdAt: block.timestamp,
            suiOrderHash: suiOrderHash,
            secret: bytes32(0),
            isWeth: true // WETH
        });
        
        emit EscrowCreatedWithWeth(
            escrowId,
            msg.sender,
            taker,
            wethAmount,
            hashLock,
            timeLock,
            suiOrderHash,
            true
        );
    }
    
    // 既存のfillEscrow関数（後方互換性）
    function fillEscrow(
        bytes32 escrowId,
        uint256 amount,
        bytes32 secret
    ) external nonReentrant {
        Escrow storage escrow = escrows[escrowId];
        
        if (escrow.maker == address(0)) revert EscrowNotFound();
        if (escrow.taker != address(0) && msg.sender != escrow.taker) revert OnlyTaker();
        if (escrow.completed) revert EscrowAlreadyCompleted();
        if (escrow.refunded) revert EscrowAlreadyRefunded();
        if (TimeLock.isExpired(escrow.timeLock)) revert EscrowExpired();
        if (amount == 0) revert InvalidFillAmount();
        if (amount > escrow.remainingAmount) revert InsufficientRemainingAmount();
        
        if (!HashLock.verifySecret(secret, escrow.hashLock)) revert InvalidSecret();
        
        if (escrow.secret == bytes32(0)) {
            if (usedSecrets[secret]) revert SecretAlreadyUsed();
            escrow.secret = secret;
            usedSecrets[secret] = true;
        } else {
            if (escrow.secret != secret) revert InvalidSecret();
        }
        
        escrow.remainingAmount -= amount;
        
        bool isCompleted = escrow.remainingAmount == 0;
        if (isCompleted) {
            escrow.completed = true;
        }
        
        // ETH送金（既存ロジック）
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();
        
        if (isCompleted) {
            emit EscrowCompleted(escrowId, msg.sender, secret, escrow.suiOrderHash);
        } else {
            emit EscrowPartiallyFilled(
                escrowId, 
                msg.sender, 
                amount, 
                escrow.remainingAmount, 
                secret, 
                escrow.suiOrderHash
            );
        }
    }
    
    // 新しいWETH対応fillEscrow関数
    function fillEscrowWithWeth(
        bytes32 escrowId,
        uint256 amount,
        bytes32 secret
    ) external nonReentrant {
        Escrow storage escrow = escrows[escrowId];
        
        if (escrow.maker == address(0)) revert EscrowNotFound();
        if (!escrow.isWeth) revert InvalidWethAmount(); // WETHエスクローのみ
        if (escrow.taker != address(0) && msg.sender != escrow.taker) revert OnlyTaker();
        if (escrow.completed) revert EscrowAlreadyCompleted();
        if (escrow.refunded) revert EscrowAlreadyRefunded();
        if (TimeLock.isExpired(escrow.timeLock)) revert EscrowExpired();
        if (amount == 0) revert InvalidFillAmount();
        if (amount > escrow.remainingAmount) revert InsufficientRemainingAmount();
        
        if (!HashLock.verifySecret(secret, escrow.hashLock)) revert InvalidSecret();
        
        if (escrow.secret == bytes32(0)) {
            if (usedSecrets[secret]) revert SecretAlreadyUsed();
            escrow.secret = secret;
            usedSecrets[secret] = true;
        } else {
            if (escrow.secret != secret) revert InvalidSecret();
        }
        
        escrow.remainingAmount -= amount;
        
        bool isCompleted = escrow.remainingAmount == 0;
        if (isCompleted) {
            escrow.completed = true;
        }
        
        // WETH送金
        weth.safeTransfer(msg.sender, amount);
        
        if (isCompleted) {
            emit EscrowCompleted(escrowId, msg.sender, secret, escrow.suiOrderHash);
        } else {
            emit EscrowPartiallyFilled(
                escrowId, 
                msg.sender, 
                amount, 
                escrow.remainingAmount, 
                secret, 
                escrow.suiOrderHash
            );
        }
    }
    
    // refundEscrow関数修正
    function refundEscrow(bytes32 escrowId) external nonReentrant {
        Escrow storage escrow = escrows[escrowId];
        
        if (escrow.maker == address(0)) revert EscrowNotFound();
        if (msg.sender != escrow.maker) revert OnlyMaker();
        if (escrow.completed) revert EscrowAlreadyCompleted();
        if (escrow.refunded) revert EscrowAlreadyRefunded();
        if (!TimeLock.isExpired(escrow.timeLock)) revert EscrowNotExpired();
        
        escrow.refunded = true;
        uint256 amount = escrow.remainingAmount;
        escrow.remainingAmount = 0;
        
        if (escrow.isWeth) {
            // WETH返還
            weth.safeTransfer(escrow.maker, amount);
        } else {
            // ETH返還（既存ロジック）
            (bool success, ) = escrow.maker.call{value: amount}("");
            if (!success) revert TransferFailed();
        }
        
        emit EscrowRefunded(escrowId, escrow.maker, amount, escrow.suiOrderHash);
    }
    
    // 新しいビュー関数
    function getEscrowWithWethInfo(bytes32 escrowId) external view returns (
        address maker,
        address taker,
        uint256 totalAmount,
        uint256 remainingAmount,
        bytes32 hashLock,
        uint256 timeLock,
        bool completed,
        bool refunded,
        uint256 createdAt,
        string memory suiOrderHash,
        bool isWeth
    ) {
        Escrow memory escrow = escrows[escrowId];
        return (
            escrow.maker,
            escrow.taker,
            escrow.totalAmount,
            escrow.remainingAmount,
            escrow.hashLock,
            escrow.timeLock,
            escrow.completed,
            escrow.refunded,
            escrow.createdAt,
            escrow.suiOrderHash,
            escrow.isWeth
        );
    }
    
    // 既存の関数は保持（後方互換性のため）
    // ...
}
```

## 2. スクリプト修正

### 2.1 環境変数追加

```env
# .env.local に追加
WETH_ADDRESS=0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9  # Sepolia WETH
```

### 2.2 ABI追加 (`scripts/verify-bidirectional-swap.ts`)

```typescript
// WETH ABI追加
const WETH_ABI = [
  {
    "inputs": [],
    "name": "deposit",
    "outputs": [],
    "stateMutability": "payable",
    "type": "function"
  },
  {
    "inputs": [{"name": "to", "type": "address"}, {"name": "amount", "type": "uint256"}],
    "name": "approve",
    "outputs": [{"name": "", "type": "bool"}],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{"name": "account", "type": "address"}],
    "name": "balanceOf",
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"name": "owner", "type": "address"}, {"name": "spender", "type": "address"}],
    "name": "allowance",
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  }
] as const;

// 更新されたESCROW_ABI
const ESCROW_ABI = [
  // 既存の関数...
  {
    "inputs": [
      {"name": "hashLock", "type": "bytes32"},
      {"name": "timeLock", "type": "uint256"},
      {"name": "taker", "type": "address"},
      {"name": "suiOrderHash", "type": "string"},
      {"name": "wethAmount", "type": "uint256"}
    ],
    "name": "createEscrowWithWeth",
    "outputs": [{"name": "", "type": "bytes32"}],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {"name": "escrowId", "type": "bytes32"},
      {"name": "amount", "type": "uint256"},
      {"name": "secret", "type": "bytes32"}
    ],
    "name": "fillEscrowWithWeth",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{"name": "escrowId", "type": "bytes32"}],
    "name": "getEscrowWithWethInfo",
    "outputs": [
      {"name": "maker", "type": "address"},
      {"name": "taker", "type": "address"},
      {"name": "totalAmount", "type": "uint256"},
      {"name": "remainingAmount", "type": "uint256"},
      {"name": "hashLock", "type": "bytes32"},
      {"name": "timeLock", "type": "uint256"},
      {"name": "completed", "type": "bool"},
      {"name": "refunded", "type": "bool"},
      {"name": "createdAt", "type": "uint256"},
      {"name": "suiOrderHash", "type": "string"},
      {"name": "isWeth", "type": "bool"}
    ],
    "stateMutability": "view",
    "type": "function"
  }
] as const;
```

### 2.3 環境変数取得追加

```typescript
// 環境変数追加
const WETH_ADDRESS = getRequiredEnvVar('WETH_ADDRESS');

// WETHコントラクト作成
const wethContract = getContract({
  address: WETH_ADDRESS as `0x${string}`,
  abi: WETH_ABI,
  publicClient,
  walletClient,
});
```

### 2.4 createEthEscrow関数修正

```typescript
private async createEthEscrow(hashLock: string, timeLock: bigint, amount: bigint): Promise<string> {
  try {
    console.log(`�� Preparing Ethereum escrow creation with WETH...`);
    console.log(`📝 Hash lock: ${hashLock}`);
    console.log(`⏰ Time lock: ${timeLock}`);
    console.log(`💰 Amount: ${formatEther(amount)} ETH`);
    console.log(`👤 Taker: ${userAccount.address}`);
    
    // 最小額チェック
    const minAmount = parseEther('0.0001');
    if (amount < minAmount) {
      console.log(`⚠️ Amount is too small. Adjusting to minimum amount: ${formatEther(minAmount)} ETH`);
      amount = minAmount;
    }
    
    // ETH残高チェック
    const balance = await publicClient.getBalance({ address: userAccount.address });
    console.log(`💰 User ETH balance: ${formatEther(balance)} ETH`);
    if (balance < amount) {
      throw new Error(`Insufficient ETH balance: ${formatEther(balance)} < ${formatEther(amount)}`);
    }
    
    // 1. ETHをWETHにラップ
    console.log(`�� Wrapping ${formatEther(amount)} ETH to WETH...`);
    const wrapHash = await walletClient.sendTransaction({
      account: userAccount,
      to: WETH_ADDRESS as `0x${string}`,
      data: encodeFunctionData({
        abi: WETH_ABI,
        functionName: 'deposit',
        args: []
      }),
      value: amount,
      gas: 100000n,
    });
    
    console.log(`📋 WETH wrap transaction: ${wrapHash}`);
    await publicClient.waitForTransactionReceipt({ hash: wrapHash });
    console.log(`✅ ETH wrapped to WETH successfully`);
    
    // 2. WETH残高確認
    const wethBalance = await wethContract.read.balanceOf([userAccount.address]);
    console.log(`�� User WETH balance: ${formatEther(wethBalance)} WETH`);
    
    // 3. WETHをエスクローコントラクトに承認
    console.log(`�� Approving WETH for escrow contract...`);
    const approveHash = await wethContract.write.approve({
      args: [this.ethEscrowAddress, amount],
      account: userAccount,
    });
    
    console.log(`📋 WETH approve transaction: ${approveHash}`);
    await publicClient.waitForTransactionReceipt({ hash: approveHash });
    console.log(`✅ WETH approved for escrow contract`);
    
    // 4. エスクロー作成（WETH使用）
    console.log(`📦 Creating escrow with WETH...`);
    const data = encodeFunctionData({
      abi: ESCROW_ABI,
      functionName: 'createEscrowWithWeth',
      args: [hashLock as `0x${string}`, BigInt(timeLock), userAccount.address, 'test-sui-order', amount],
    });
    
    const gasPrice = await publicClient.getGasPrice();
    const optimizedGasPrice = (gasPrice * 120n) / 100n;
    
    const hash = await walletClient.sendTransaction({
      account: userAccount,
      to: this.ethEscrowAddress as `0x${string}`,
      data,
      value: 0n, // ETHは送金しない
      gasPrice: optimizedGasPrice,
      gas: 500000n,
    });
    
    console.log(`📋 Escrow creation transaction: ${hash}`);
    this.ethSentTxHashes = [hash];
    
    const receipt = await publicClient.waitForTransactionReceipt({ 
      hash,
      timeout: 60000,
      pollingInterval: 2000
    });
    
    console.log(`📋 Transaction completed: ${receipt.status}`);
    
    if (receipt.status === 'success') {
      // エスクローID取得
      const logs = await publicClient.getLogs({
        address: this.ethEscrowAddress as `0x${string}`,
        fromBlock: receipt.blockNumber,
        toBlock: receipt.blockNumber,
        event: {
          type: 'event',
          name: 'EscrowCreatedWithWeth',
          inputs: [
            { type: 'bytes32', name: 'escrowId', indexed: true },
            { type: 'address', name: 'maker', indexed: true },
            { type: 'address', name: 'taker', indexed: true },
            { type: 'uint256', name: 'amount', indexed: false },
            { type: 'bytes32', name: 'hashLock', indexed: false },
            { type: 'uint256', name: 'timeLock', indexed: false },
            { type: 'string', name: 'suiOrderHash', indexed: false },
            { type: 'bool', name: 'isWeth', indexed: false }
          ]
        }
      });
      
      if (logs.length > 0) {
        const escrowId = logs[0].args.escrowId;
        if (escrowId) {
          console.log(`�� WETH Escrow ID: ${escrowId}`);
          
          const exists = await this.verifyEscrowExists(escrowId);
          if (exists) {
            console.log(`✅ WETH escrow creation confirmed`);
            return escrowId;
          } else {
            throw new Error('WETH escrow was not created correctly');
          }
        }
      }
      
      // フォールバック: エスクローID計算
      const currentTimestamp = Math.floor(Date.now() / 1000);
      const escrowId = keccak256(
        encodePacked(
          ['address', 'address', 'uint256', 'bytes32', 'uint256', 'uint256', 'uint256'],
          [userAccount.address as `0x${string}`, userAccount.address as `0x${string}`, amount, hashLock as `0x${string}`, timeLock, BigInt(currentTimestamp), BigInt(receipt.blockNumber)]
        )
      );
      
      console.log(`📦 WETH Escrow ID calculated: ${escrowId}`);
      return escrowId;
    } else {
      throw new Error('WETH escrow creation failed');
    }
    
  } catch (error) {
    console.error('❌ WETH escrow creation error:', error);
    throw error;
  }
}
```

### 2.5 fillEthEscrow関数修正

```typescript
private async fillEthEscrow(escrowId: string, amount: bigint, secret: string, isEthToSui: boolean = true): Promise<void> {
  try {
    console.log(`�� Preparing WETH escrow fill...`);
    console.log(`📦 Escrow ID: ${escrowId}`);
    console.log(`💰 Total amount: ${formatEther(amount)} WETH`);
    console.log(`�� Secret: ${secret}`);

    // エスクロー情報取得（WETH対応）
    const escrowInfo = await this.getEscrowWithWethInfo(escrowId);
    console.log(`🔍 Pre-escrow verification:`);
    console.log(`  💰 Remaining amount: ${formatEther(escrowInfo.remainingAmount)} WETH`);
    console.log(`  ✅ Completed: ${escrowInfo.completed}`);
    console.log(`  ❌ Refunded: ${escrowInfo.refunded}`);
    console.log(`  🔒 Hash lock: ${escrowInfo.hashLock}`);
    console.log(`  🪙 Is WETH: ${escrowInfo.isWeth}`);

    if (escrowInfo.completed) {
      throw new Error('Escrow is already completed');
    }
    if (escrowInfo.refunded) {
      throw new Error('Escrow is already refunded');
    }
    if (amount > escrowInfo.remainingAmount) {
      throw new Error(`Requested amount (${formatEther(amount)} WETH) exceeds remaining amount (${formatEther(escrowInfo.remainingAmount)} WETH)`);
    }

    // シークレット検証
    const calculatedHash = createHashLock(secret);
    const isValidSecret = verifySecret(secret, escrowInfo.hashLock);
    console.log(`🔍 Secret verification:`);
    console.log(`  🔑 Secret: ${secret}`);
    console.log(`  🔒 Calculated hash: ${calculatedHash}`);
    console.log(`  �� Stored hash: ${escrowInfo.hashLock}`);
    console.log(`  ✅ Verification result: ${isValidSecret}`);

    if (!isValidSecret) {
      throw new Error('Secret does not match hash lock');
    }

    // 部分フィル: Resolver2が半分を処理
    const halfAmount = amount / BigInt(2);
    console.log(`�� Resolver2 starting partial fill: ${formatEther(halfAmount)} WETH`);
    
    const data1 = encodeFunctionData({
      abi: ESCROW_ABI,
      functionName: 'fillEscrowWithWeth',
      args: [escrowId as `0x${string}`, halfAmount, secret as `0x${string}`],
    });

    console.log(`📤 Sending Resolver2 transaction...`);
    
    const gasPrice = await publicClient.getGasPrice();
    const optimizedGasPrice = (gasPrice * 120n) / 100n;
    
    const hash1 = await walletClient.sendTransaction({
      account: resolver2Account,
      to: this.ethEscrowAddress as `0x${string}`,
      data: data1,
      gasPrice: optimizedGasPrice,
      gas: 100000n,
    });
    console.log(`📋 Resolver2 transaction hash: ${hash1}`);
    
    const receipt1 = await publicClient.waitForTransactionReceipt({ 
      hash: hash1,
      timeout: 60000,
      pollingInterval: 2000
    });
    console.log(`✅ Resolver2 transaction completed: ${receipt1.status}`);
    
    // Resolver2が受信したWETHをユーザーに転送
    console.log(`🔄 Resolver2 transferring WETH to user: ${formatEther(halfAmount)} WETH`);
    
    // Resolver2がWETHをETHにアンラップしてから送金
    const unwrapData = encodeFunctionData({
      abi: WETH_ABI,
      functionName: 'withdraw',
      args: [halfAmount],
    });
    
    const unwrapHash1 = await walletClient.sendTransaction({
      account: resolver2Account,
      to: WETH_ADDRESS as `0x${string}`,
      data: unwrapData,
      gasPrice: optimizedGasPrice,
      gas: 100000n,
    });
    console.log(`�� Resolver2 WETH unwrap transaction: ${unwrapHash1}`);
    
    const unwrapReceipt1 = await publicClient.waitForTransactionReceipt({ 
      hash: unwrapHash1,
      timeout: 60000,
      pollingInterval: 2000
    });
    console.log(`✅ Resolver2 WETH unwrap completed: ${unwrapReceipt1.status}`);
    
    // ETHをユーザーに送金
    const transferHash1 = await walletClient.sendTransaction({
      account: resolver2Account,
      to: userAccount.address as `0x${string}`,
      value: halfAmount,
      gasPrice: optimizedGasPrice,
      gas: 21000n,
    });
    console.log(`📋 Resolver2 ETH transfer hash: ${transferHash1}`);
    
    const transferReceipt1 = await publicClient.waitForTransactionReceipt({ 
      hash: transferHash1,
      timeout: 60000,
      pollingInterval: 2000
    });
    console.log(`✅ Resolver2 ETH transfer completed: ${transferReceipt1.status}`);
    console.log(`�� Resolver2 transfer transaction: https://sepolia.etherscan.io/tx/${transferHash1}`);
    
    // Resolver3が残りを処理
    const remainingAmount = amount - halfAmount;
    console.log(`�� Resolver3 starting partial fill: ${formatEther(remainingAmount)} WETH`);
    
    const data2 = encodeFunctionData({
      abi: ESCROW_ABI,
      functionName: 'fillEscrowWithWeth',
      args: [escrowId as `0x${string}`, remainingAmount, secret as `0x${string}`],
    });

    const hash2 = await walletClient.sendTransaction({
      account: resolver3Account,
      to: this.ethEscrowAddress as `0x${string}`,
      data: data2,
      gasPrice: optimizedGasPrice,
      gas: 100000n,
    });
    console.log(`📋 Resolver3 transaction hash: ${hash2}`);
    
    const receipt2 = await publicClient.waitForTransactionReceipt({ 
      hash: hash2,
      timeout: 60000,
      pollingInterval: 2000
    });
    console.log(`✅ Resolver3 transaction completed: ${receipt2.status}`);
    
    // Resolver3がWETHをETHにアンラップしてから送金
    const unwrapHash2 = await walletClient.sendTransaction({
      account: resolver3Account,
      to: WETH_ADDRESS as `0x${string}`,
      data: unwrapData,
      gasPrice: optimizedGasPrice,
      gas: 100000n,
    });
    console.log(`�� Resolver3 WETH unwrap transaction: ${unwrapHash2}`);
    
    const unwrapReceipt2 = await publicClient.waitForTransactionReceipt({ 
      hash: unwrapHash2,
      timeout: 60000,
      pollingInterval: 2000
    });
    console.log(`✅ Resolver3 WETH unwrap completed: ${unwrapReceipt2.status}`);
    
    // ETHをユーザーに送金
    const transferHash2 = await walletClient.sendTransaction({
      account: resolver3Account,
      to: userAccount.address as `0x${string}`,
      value: remainingAmount,
      gasPrice: optimizedGasPrice,
      gas: 21000n,
    });
    console.log(`📋 Resolver3 ETH transfer hash: ${transferHash2}`);
    
    const transferReceipt2 = await publicClient.waitForTransactionReceipt({ 
      hash: transferHash2,
      timeout: 60000,
      pollingInterval: 2000
    });
    console.log(`✅ Resolver3 ETH transfer completed: ${transferReceipt2.status}`);
    console.log(`�� Resolver3 transfer transaction: https://sepolia.etherscan.io/tx/${transferHash2}`);
    
    console.log(`✅ WETH escrow fill completed (partial fill by 2 resolvers)`);
    console.log(`📋 Fill details:`);
    console.log(`  👤 Resolver2: ${formatEther(halfAmount)} WETH → ${formatEther(halfAmount)} ETH → ${userAccount.address}`);
    console.log(`  👤 Resolver3: ${formatEther(remainingAmount)} WETH → ${formatEther(remainingAmount)} ETH → ${userAccount.address}`);
    console.log(`  💰 Total: ${formatEther(amount)} WETH → ${formatEther(amount)} ETH`);
    
    // トランザクションハッシュ保存
    if (isEthToSui) {
      this.ethSentTxHashes = [transferHash1, transferHash2];
    } else {
      this.ethReceivedTxHashes = [transferHash1, transferHash2];
    }
    
  } catch (error) {
    console.error('❌ WETH escrow fill error:', error);
    throw error;
  }
}
```

### 2.6 getEscrowWithWethInfo関数追加

```typescript
private async getEscrowWithWethInfo(escrowId: string) {
  try {
    const escrow = await publicClient.readContract({
      address: this.ethEscrowAddress as `0x${string}`,
      abi: ESCROW_ABI,
      functionName: 'getEscrowWithWethInfo',
      args: [escrowId as `0x${string}`],
    });
    
    const [maker, taker, totalAmount, remainingAmount, hashLock, timeLock, completed, refunded, createdAt, suiOrderHash, isWeth] = escrow;
    
    return {
      maker,
      taker,
      totalAmount,
      remainingAmount,
      hashLock,
      timeLock,
      completed,
      refunded,
      createdAt,
      suiOrderHash,
      isWeth
    };
  } catch (error) {
    console.error('❌ WETH escrow info retrieval error:', error);
    throw error;
  }
}
```

## 3. デプロイメント修正

### 3.1 デプロイスクリプト修正 (`eth-contract/script/DeployEscrow.s.sol`)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {EthereumEscrow} from "../src/core/EthereumEscrow.sol";

contract DeployEscrow is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Sepolia WETHアドレス
        address wethAddress = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
        
        EthereumEscrow escrow = new EthereumEscrow(wethAddress);
        
        vm.stopBroadcast();
        
        console.log("EthereumEscrow deployed at:", address(escrow));
        console.log("WETH address:", wethAddress);
    }
}
```

## 4. テスト修正

### 4.1 テストファイル修正 (`eth-contract/test/EthereumEscrow.t.sol`)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {EthereumEscrow} from "../src/core/EthereumEscrow.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract EthereumEscrowTest is Test {
    EthereumEscrow public escrow;
    IERC20 public weth;
    
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    
    function setUp() public {
        // Sepolia WETHアドレス
        address wethAddress = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
        escrow = new EthereumEscrow(wethAddress);
        weth = IERC20(wethAddress);
        
        // テスト用ETH配布
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }
    
    function testCreateEscrowWithWeth() public {
        vm.startPrank(alice);
        
        // ETHをWETHにラップ
        (bool success,) = address(weth).call{value: 1 ether}("");
        require(success, "WETH wrap failed");
        
        // WETHを承認
        weth.approve(address(escrow), 1 ether);
        
        // エスクロー作成
        bytes32 hashLock = keccak256(abi.encodePacked("secret"));
        uint256 timeLock = block.timestamp + 1 hours;
        
        bytes32 escrowId = escrow.createEscrowWithWeth(
            hashLock,
            timeLock,
            payable(bob),
            "test-order",
            1 ether
        );
        
        // エスクロー情報確認
        (address maker, address taker, uint256 totalAmount, uint256 remainingAmount, , , , , , , bool isWeth) = escrow.getEscrowWithWethInfo(escrowId);
        
        assertEq(maker, alice);
        assertEq(taker, bob);
        assertEq(totalAmount, 1 ether);
        assertEq(remainingAmount, 1 ether);
        assertTrue(isWeth);
        
        vm.stopPrank();
    }
    
    function testFillEscrowWithWeth() public {
        vm.startPrank(alice);
        
        // ETHをWETHにラップ
        (bool success,) = address(weth).call{value: 1 ether}("");
        require(success, "WETH wrap failed");
        
        // WETHを承認
        weth.approve(address(escrow), 1 ether);
        
        // エスクロー作成
        bytes32 hashLock = keccak256(abi.encodePacked("secret"));
        uint256 timeLock = block.timestamp + 1 hours;
        
        bytes32 escrowId = escrow.createEscrowWithWeth(
            hashLock,
            timeLock,
            payable(bob),
            "test-order",
            1 ether
        );
        
        vm.stopPrank();
        
        // Bobがエスクローを埋める
        vm.startPrank(bob);
        
        bytes32 secret = keccak256(abi.encodePacked("secret"));
        escrow.fillEscrowWithWeth(escrowId, 1 ether, secret);
        
        // WETH残高確認
        uint256 bobWethBalance = weth.balanceOf(bob);
        assertEq(bobWethBalance, 1 ether);
        
        vm.stopPrank();
    }
}
```

## 5. 実行手順

### 5.1 コントラクトデプロイ

```bash
cd eth-contract
forge script script/DeployEscrow.s.sol --rpc-url https://sepolia.drpc.org --broadcast
```

### 5.2 環境変数更新

```env
# .env.local
ETH_ESCROW_ADDRESS=<新しくデプロイされたアドレス>
WETH_ADDRESS=0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9
```

### 5.3 スクリプト実行

```bash
cd scripts
npm run test
```

## 6. 修正の利点

1. **標準準拠**: WETHを使用することでERC20標準に準拠
2. **互換性向上**: 他のDEXやプロトコルとの統合が容易
3. **セキュリティ向上**: WETHの標準的な処理により安全性向上
4. **後方互換性**: 既存のETH直接処理も保持

## 7. 注意事項

1. **ガス代増加**: WETHラップ/アンラップによりガス代が増加
2. **複雑性増加**: より多くのトランザクションが必要
3. **テスト重要性**: 十分なテストが必要
4. **段階的移行**: 既存システムとの互換性を保ちながら移行

この修正により、標準的なクロスチェーンswap実装となります。

// Resolver service to simulate the resolver behavior from scripts
import { createPublicClient, createWalletClient, http, encodeFunctionData, formatEther } from 'viem'
import { sepolia } from 'viem/chains'
import { privateKeyToAccount } from 'viem/accounts'
import { Transaction } from '@mysten/sui/transactions'
import { SuiClient } from '@mysten/sui/client'
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519'
import { getFaucetHost, requestSuiFromFaucetV2 } from '@mysten/sui/faucet'

// Environment variables
const ETH_ESCROW_ADDRESS = import.meta.env.VITE_ETH_ESCROW_ADDRESS
const SUI_ESCROW_PACKAGE_ID = import.meta.env.VITE_SUI_ESCROW_PACKAGE_ID
const SUI_USED_SECRETS_REGISTRY_ID = import.meta.env.VITE_SUI_USED_SECRETS_REGISTRY_ID

const RESOLVER2_PRIVATE_KEY = import.meta.env.VITE_RESOLVER2_PRIVATE_KEY
const RESOLVER3_PRIVATE_KEY = import.meta.env.VITE_RESOLVER3_PRIVATE_KEY
const SUI_RESOLVER2_PRIVATE_KEY = import.meta.env.VITE_SUI_RESOLVER2_PRIVATE_KEY
const SUI_RESOLVER3_PRIVATE_KEY = import.meta.env.VITE_SUI_RESOLVER3_PRIVATE_KEY

// Ethereum resolver accounts
const resolver2Account = privateKeyToAccount(RESOLVER2_PRIVATE_KEY as `0x${string}`)
const resolver3Account = privateKeyToAccount(RESOLVER3_PRIVATE_KEY as `0x${string}`)

// Sui resolver keypairs - same as scripts (generate new keypairs for demo)
const suiResolver2Keypair = new Ed25519Keypair()
const suiResolver3Keypair = new Ed25519Keypair()

// Ethereum client
const publicClient = createPublicClient({
  chain: sepolia,
  transport: http(import.meta.env.VITE_ETHEREUM_RPC_URL)
})

// Sui client
const suiClient = new SuiClient({
  url: import.meta.env.VITE_SUI_RPC_URL || 'https://fullnode.devnet.sui.io:443'
})

const ESCROW_ABI = [
  {
    "inputs": [
      {"name": "escrowId", "type": "bytes32"},
      {"name": "amount", "type": "uint256"},
      {"name": "secret", "type": "bytes32"}
    ],
    "name": "fillEscrow",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  }
] as const

// Helper function: Convert hex string to byte array
function hexStringToBytes(hexString: string): number[] {
  const hex = hexString.startsWith('0x') ? hexString.slice(2) : hexString
  const bytes: number[] = []
  for (let i = 0; i < hex.length; i += 2) {
    bytes.push(parseInt(hex.substring(i, i + 2), 16))
  }
  return bytes
}

// Helper function: Convert hex string to byte array for Sui
function hexStringToBytesForSui(hexString: string): number[] {
  const hex = hexString.startsWith('0x') ? hexString.slice(2) : hexString
  const bytes: number[] = []
  for (let i = 0; i < hex.length; i += 2) {
    bytes.push(parseInt(hex.substring(i, i + 2), 16))
  }
  return bytes
}

export class ResolverService {
  private addLog: (message: string) => void
  public ethReceivedTxHashes: string[] = []
  public suiReceivedTxHashes: string[] = []

  constructor(addLog: (message: string) => void) {
    this.addLog = addLog
  }

  // Ensure Sui balance for resolver (same as scripts)
  async ensureSuiBalance(address: string, requiredAmount: bigint = BigInt(10000000000)): Promise<void> {
    try {
      this.addLog(`🔍 Checking Sui account balance: ${address}`)
      
      const coins = await suiClient.getCoins({
        owner: address,
        coinType: '0x2::sui::SUI'
      })
      
      let totalBalance = BigInt(0)
      for (const coin of coins.data) {
        totalBalance += BigInt(coin.balance)
      }
      
      this.addLog(`💰 Current total balance: ${Number(totalBalance) / 1e9} SUI`)
      
      if (totalBalance < requiredAmount) {
        this.addLog(`⚠️ Balance is insufficient. Getting tokens from faucet...`)
        await this.requestSuiFromFaucet(address)
        
        // Check balance after obtaining using simplified method
        await new Promise(resolve => setTimeout(resolve, 2000))
        const updatedCoins = await suiClient.getCoins({
          owner: address,
          coinType: '0x2::sui::SUI'
        })
        
        let updatedBalance = BigInt(0)
        for (const coin of updatedCoins.data) {
          updatedBalance += BigInt(coin.balance)
        }
        
        this.addLog(`💰 Updated balance: ${Number(updatedBalance) / 1e9} SUI`)
        
        if (updatedBalance < requiredAmount) {
          this.addLog(`⚠️ Balance is still insufficient but continuing. Required: ${Number(requiredAmount) / 1e9}, Current: ${Number(updatedBalance) / 1e9}`)
        }
      } else {
        this.addLog(`✅ Balance is sufficient`)
      }
      
    } catch (error) {
      this.addLog(`❌ Sui balance check error: ${error instanceof Error ? error.message : 'Unknown error'}`)
      throw error
    }
  }

  // Request SUI from faucet (same as scripts)
  async requestSuiFromFaucet(address: string): Promise<void> {
    try {
      this.addLog(`💰 Requesting tokens from Sui faucet...`)
      this.addLog(`📧 Address: ${address}`)
      
      await requestSuiFromFaucetV2({
        host: getFaucetHost('devnet'),
        recipient: address,
      })
      
      this.addLog(`✅ Obtained tokens from Sui faucet`)
      
      // Wait a bit for the transaction to be processed
      await new Promise(resolve => setTimeout(resolve, 1000))
      
      // Check balance after obtaining
      const coins = await suiClient.getCoins({
        owner: address,
        coinType: '0x2::sui::SUI'
      })
      
      const balance = coins.data.reduce((total, coin) => total + BigInt(coin.balance), BigInt(0))
      this.addLog(`💰 Balance after faucet: ${Number(balance) / 1e9} SUI`)
      
    } catch (error) {
      this.addLog(`❌ Failed to get tokens from Sui faucet: ${error instanceof Error ? error.message : 'Unknown error'}`)
      throw error
    }
  }

  // Create Sui escrow with resolver keypair (for ETH→SUI swaps) - exact copy from scripts
  async createSuiEscrowWithResolver(hashLock: string, timeLock: bigint, amount: bigint): Promise<string> {
    this.addLog(`🔧 Resolver creating Sui escrow...`)
    this.addLog(`💰 Amount: ${Number(amount) / 1e9} SUI`)
    this.addLog(`⏰ Time lock: ${timeLock}`)
    this.addLog(`🔒 Hash lock: ${hashLock}`)

    try {
      // Get resolver address
      const address = suiResolver2Keypair.getPublicKey().toSuiAddress()
      this.addLog(`🔍 Checking Sui resolver account: ${address}`)
      
      // Check balance and get from faucet if necessary (same as scripts)
      await this.ensureSuiBalance(address, BigInt(3000000000)) // 3 SUI - adjusted to minimum required
      
      const transaction = new Transaction()
      
      // Get gas coins and perform necessary validation (same as scripts)
      const gasCoins = await suiClient.getCoins({
        owner: address,
        coinType: '0x2::sui::SUI'
      })
      
      if (gasCoins.data.length === 0) {
        throw new Error('Gas coins not found for resolver')
      }
      
      if (amount <= 0) {
        throw new Error(`Invalid amount: ${amount}`)
      }
      
      const gasCoin = gasCoins.data[0]
      if (BigInt(gasCoin.balance) < amount) {
        throw new Error(`Insufficient gas coin balance: ${gasCoin.balance} < ${amount}`)
      }
      
      // Set gas payment explicitly (same as scripts)
      transaction.setGasPayment([{
        version: gasCoin.version,
        objectId: gasCoin.coinObjectId,
        digest: gasCoin.digest
      }])
      
      this.addLog(`🔧 Preparing Sui transaction...`)
      this.addLog(`⛽ Gas coin: ${gasCoin.coinObjectId}`)
      
      // Get Sui coins (split from gas coin) - same as scripts
      const [coin] = transaction.splitCoins(transaction.gas, [Number(amount)])

      // Call escrow creation function - same as scripts
      transaction.moveCall({
        target: `${SUI_ESCROW_PACKAGE_ID}::cross_chain_escrow::create_and_share_escrow`,
        typeArguments: ['0x2::sui::SUI'],
        arguments: [
          coin,
          transaction.pure.address('0x0'), // taker (anyone can take)
          transaction.pure.vector('u8', hexStringToBytesForSui(hashLock) as number[]),
          transaction.pure.u64(timeLock),
          transaction.pure.string('test-eth-order'),
          transaction.object('0x6'), // Clock object
        ],
      })

      this.addLog(`🔧 Sui transaction preparation completed`)

      // Execute transaction with same options as scripts
      const result = await suiClient.signAndExecuteTransaction({
        transaction,
        signer: suiResolver2Keypair,
        options: {
          showEffects: true,
          showObjectChanges: true,
        },
        requestType: 'WaitForLocalExecution', // Same as scripts
      })

      this.addLog(`📋 Transaction result: ${result.digest}`)
      
      // Get escrow ID from object changes (same as scripts)
      const createdObject = result.objectChanges?.find(
        change => change.type === 'created' && change.objectType?.includes('CrossChainEscrow')
      )

      if (createdObject && createdObject.type === 'created') {
        const escrowId = createdObject.objectId
        this.addLog(`📦 Escrow ID retrieved from object changes: ${escrowId}`)
        return escrowId
      } else {
        // Fallback: return transaction digest
        this.addLog(`⚠️ Could not retrieve escrow ID from object changes. Using transaction digest.`)
        return result.digest
      }

    } catch (error) {
      this.addLog(`❌ Failed to create Sui escrow: ${error instanceof Error ? error.message : 'Unknown error'}`)
      throw error
    }
  }

  // Create Ethereum escrow with resolver (for SUI→ETH swaps)  
  async createEthEscrowWithResolver(hashLock: string, timeLock: bigint, amount: bigint): Promise<string> {
    this.addLog(`🔧 Resolver creating Ethereum escrow...`)
    this.addLog(`💰 Amount: ${formatEther(amount)} ETH`)
    this.addLog(`⏰ Time lock: ${timeLock}`)
    this.addLog(`🔒 Hash lock: ${hashLock}`)

    const walletClient = createWalletClient({
      account: resolver2Account,
      chain: sepolia,
      transport: http(import.meta.env.VITE_ETHEREUM_RPC_URL)
    })

    // Encode function data
    const data = encodeFunctionData({
      abi: [{
        "inputs": [
          {"name": "hashLock", "type": "bytes32"},
          {"name": "timeLock", "type": "uint256"},
          {"name": "taker", "type": "address"},
          {"name": "suiOrderHash", "type": "string"}
        ],
        "name": "createEscrow",
        "outputs": [{"name": "", "type": "bytes32"}],
        "stateMutability": "payable",
        "type": "function"
      }] as const,
      functionName: 'createEscrow',
      args: [hashLock as `0x${string}`, timeLock, resolver2Account.address, 'test-sui-order']
    })

    const hash = await walletClient.sendTransaction({
      account: resolver2Account,
      to: ETH_ESCROW_ADDRESS as `0x${string}`,
      data,
      value: amount,
      gas: 500000n
    })

    this.addLog(`📋 Resolver created Ethereum escrow: ${hash}`)
    return hash
  }

  // Fill Ethereum Escrow with resolvers (same as scripts)
  async fillEthEscrowWithResolvers(escrowId: string, amount: bigint, secret: string, userAddress: string): Promise<void> {
    this.addLog(`🔄 Starting resolver fill of Ethereum escrow...`)
    this.addLog(`📦 Escrow ID: ${escrowId}`)
    this.addLog(`💰 Total amount: ${formatEther(amount)} ETH`)

    // Wait for initial transaction confirmation
    await new Promise(resolve => setTimeout(resolve, 3000))

    // Partial fill: Resolver2 fills half
    const halfAmount = amount / BigInt(2)
    this.addLog(`🔄 Resolver2 starting partial fill: ${formatEther(halfAmount)} ETH`)

    const walletClient2 = createWalletClient({
      account: resolver2Account,
      chain: sepolia,
      transport: http(import.meta.env.VITE_ETHEREUM_RPC_URL)
    })

    const data1 = encodeFunctionData({
      abi: ESCROW_ABI,
      functionName: 'fillEscrow',
      args: [escrowId as `0x${string}`, halfAmount, secret as `0x${string}`]
    })

    const hash1 = await walletClient2.sendTransaction({
      account: resolver2Account,
      to: ETH_ESCROW_ADDRESS as `0x${string}`,
      data: data1,
      gas: 100000n
    })

    this.addLog(`📋 Resolver2 transaction hash: ${hash1}`)

    // Resolver2 transfers to user
    const transferHash1 = await walletClient2.sendTransaction({
      account: resolver2Account,
      to: userAddress as `0x${string}`,
      value: halfAmount,
      gas: 21000n
    })

    this.addLog(`✅ Resolver2 transferred ${formatEther(halfAmount)} ETH to user: ${transferHash1}`)
    this.ethReceivedTxHashes.push(transferHash1)

    // Wait between resolver actions
    await new Promise(resolve => setTimeout(resolve, 2000))

    // Partial fill: Resolver3 fills remainder
    const remainingAmount = amount - halfAmount
    this.addLog(`🔄 Resolver3 starting partial fill: ${formatEther(remainingAmount)} ETH`)

    const walletClient3 = createWalletClient({
      account: resolver3Account,
      chain: sepolia,
      transport: http(import.meta.env.VITE_ETHEREUM_RPC_URL)
    })

    const data2 = encodeFunctionData({
      abi: ESCROW_ABI,
      functionName: 'fillEscrow',
      args: [escrowId as `0x${string}`, remainingAmount, secret as `0x${string}`]
    })

    const hash2 = await walletClient3.sendTransaction({
      account: resolver3Account,
      to: ETH_ESCROW_ADDRESS as `0x${string}`,
      data: data2,
      gas: 100000n
    })

    this.addLog(`📋 Resolver3 transaction hash: ${hash2}`)

    // Resolver3 transfers to user
    const transferHash2 = await walletClient3.sendTransaction({
      account: resolver3Account,
      to: userAddress as `0x${string}`,
      value: remainingAmount,
      gas: 21000n
    })

    this.addLog(`✅ Resolver3 transferred ${formatEther(remainingAmount)} ETH to user: ${transferHash2}`)
    this.ethReceivedTxHashes.push(transferHash2)
    this.addLog(`🎉 Ethereum escrow fill completed by resolvers!`)
  }

  // Fill Sui Escrow with resolvers (same as scripts)
  async fillSuiEscrowWithResolvers(escrowId: string, amount: bigint, secret: string, userAddress: string): Promise<void> {
    this.addLog(`🔄 Starting resolver fill of Sui escrow...`)
    this.addLog(`📦 Escrow ID: ${escrowId}`)
    this.addLog(`💰 Total amount: ${Number(amount) / 1e9} SUI`)

    // Check balance and get from faucet if necessary (same as scripts)
    const resolver2Address = suiResolver2Keypair.getPublicKey().toSuiAddress()
    const resolver3Address = suiResolver3Keypair.getPublicKey().toSuiAddress()
    await this.ensureSuiBalance(resolver2Address, BigInt(2000000000)) // 2 SUI - adjusted to minimum required
    await this.ensureSuiBalance(resolver3Address, BigInt(2000000000)) // 2 SUI - adjusted to minimum required

    // Wait for initial transaction confirmation
    await new Promise(resolve => setTimeout(resolve, 3000))

    // Partial fill: Resolver2 fills half
    const halfAmount = amount / BigInt(2)
    this.addLog(`🔄 Sui Resolver2 starting partial fill: ${Number(halfAmount) / 1e9} SUI`)

    const transaction1 = new Transaction()
    const escrow1 = transaction1.object(escrowId as `0x${string}`)
    const registry1 = transaction1.object(SUI_USED_SECRETS_REGISTRY_ID as `0x${string}`)

    const [receivedCoin1] = transaction1.moveCall({
      target: `${SUI_ESCROW_PACKAGE_ID}::cross_chain_escrow::fill_escrow_partial`,
      typeArguments: ['0x2::sui::SUI'],
      arguments: [
        escrow1,
        registry1,
        transaction1.pure.u64(halfAmount),
        transaction1.pure.vector('u8', hexStringToBytes(secret) as number[]),
        transaction1.object('0x6')
      ]
    })

    transaction1.transferObjects([receivedCoin1], transaction1.pure.address(userAddress))

    const result1 = await suiClient.signAndExecuteTransaction({
      transaction: transaction1,
      signer: suiResolver2Keypair,
      options: { showEffects: true }
    })

    this.addLog(`✅ Sui Resolver2 transferred ${Number(halfAmount) / 1e9} SUI to user: ${result1.digest}`)
    this.suiReceivedTxHashes.push(result1.digest)

    // Wait between resolver actions
    await new Promise(resolve => setTimeout(resolve, 2000))

    // Partial fill: Resolver3 fills remainder
    const remainingAmount = amount - halfAmount
    this.addLog(`🔄 Sui Resolver3 starting partial fill: ${Number(remainingAmount) / 1e9} SUI`)

    const transaction2 = new Transaction()
    const escrow2 = transaction2.object(escrowId as `0x${string}`)
    const registry2 = transaction2.object(SUI_USED_SECRETS_REGISTRY_ID as `0x${string}`)

    const [receivedCoin2] = transaction2.moveCall({
      target: `${SUI_ESCROW_PACKAGE_ID}::cross_chain_escrow::fill_escrow_partial`,
      typeArguments: ['0x2::sui::SUI'],
      arguments: [
        escrow2,
        registry2,
        transaction2.pure.u64(remainingAmount),
        transaction2.pure.vector('u8', hexStringToBytes(secret) as number[]),
        transaction2.object('0x6')
      ]
    })

    transaction2.transferObjects([receivedCoin2], transaction2.pure.address(userAddress))

    const result2 = await suiClient.signAndExecuteTransaction({
      transaction: transaction2,
      signer: suiResolver3Keypair,
      options: { showEffects: true }
    })

    this.addLog(`✅ Sui Resolver3 transferred ${Number(remainingAmount) / 1e9} SUI to user: ${result2.digest}`)
    this.suiReceivedTxHashes.push(result2.digest)
    this.addLog(`🎉 Sui escrow fill completed by resolvers!`)
  }
}
import { useState } from 'react'
import { ConnectButton } from '@rainbow-me/rainbowkit'
import { ConnectButton as SuiConnectButton, useCurrentAccount } from '@mysten/dapp-kit'
import { useAccount, useBalance } from 'wagmi'
import { formatEther, parseEther } from 'viem'
import { useSuiWallet } from './hooks/useSuiWallet'
import { useCompleteSwap } from './hooks/useCompleteSwap'
import './App.css'

function App() {
  const [amount, setAmount] = useState('')
  const [swapDirection, setSwapDirection] = useState<'eth-to-sui' | 'sui-to-eth'>('eth-to-sui')

  // Ethereum wallet
  const { address: ethAddress, isConnected: ethConnected } = useAccount()
  const { data: ethBalance } = useBalance({ address: ethAddress })

  // Sui wallet
  const suiAccount = useCurrentAccount()
  const { balance: suiBalance, requestFromFaucet, isLoading: faucetLoading } = useSuiWallet()

  // Swap functionality
  const {
    isLoading: swapLoading,
    logs,
    clearLogs,
    swapEthToSui,
    swapSuiToEth,
    calculateEthToSuiAmount,
    calculateSuiToEthAmount,
    transactionHistory,
    showTransactionHistory
  } = useCompleteSwap()

  const bothWalletsConnected = ethConnected && suiAccount?.address
  const isLoading = swapLoading || faucetLoading

  const handleSwap = async () => {
    if (!bothWalletsConnected) {
      alert('Please connect both Ethereum and Sui wallets')
      return
    }

    if (!amount) {
      alert('Please enter amount')
      return
    }

    clearLogs()

    try {
      if (swapDirection === 'eth-to-sui') {
        const ethAmount = parseEther(amount)
        await swapEthToSui(ethAmount)
      } else {
        const suiAmount = BigInt(parseFloat(amount) * 1e9)
        await swapSuiToEth(suiAmount)
      }
    } catch (error) {
      console.error('Swap failed:', error)
    }
  }

  const getReceiveAmount = () => {
    if (!amount || parseFloat(amount) <= 0) return '0'

    if (swapDirection === 'eth-to-sui') {
      const ethAmount = parseEther(amount)
      // 1 ETH = 1000 SUI (same calculation as scripts)
      const suiReceive = (ethAmount * BigInt(1000 * 1e9)) / BigInt(1e18)
      return `${(Number(suiReceive) / 1e9).toFixed(6)} SUI`
    } else {
      const suiAmount = BigInt(parseFloat(amount) * 1e9)
      // 1000 SUI = 1 ETH (same calculation as scripts)
      const ethReceive = (suiAmount * BigInt(1e18)) / BigInt(1000 * 1e9)
      return `${formatEther(ethReceive)} ETH`
    }
  }

  return (
    <div className="app">
      <header className="header">
        <h1>
          <img src="/logo.png" alt="Unite Sui" className="logo" />
          Unite Sui Cross-Chain Swap
        </h1>
        <p className="subtitle">🪙 Enhanced with Limit Order Protocol integration</p>
        <div className="wallet-buttons">
          <ConnectButton />
          <SuiConnectButton />
        </div>
      </header>

      <main className="main">
        {/* Wallet Status */}
        <div className="wallet-status">
          <div className="wallet-card">
            <h3>Ethereum (Sepolia)</h3>
            <p>Status: {ethConnected ? '✅ Connected' : '❌ Disconnected'}</p>
            {ethConnected && (
              <>
                <p>Address: {ethAddress?.slice(0, 8)}...{ethAddress?.slice(-6)}</p>
                <p>Balance: {ethBalance ? formatEther(ethBalance.value) : '0'} ETH</p>
              </>
            )}
          </div>

          <div className="wallet-card">
            <h3>Sui (Devnet)</h3>
            <p>Status: {suiAccount ? '✅ Connected' : '❌ Disconnected'}</p>
            {suiAccount && (
              <>
                <p>Address: {suiAccount.address.slice(0, 8)}...{suiAccount.address.slice(-6)}</p>
                <p>Balance: {suiBalance} SUI</p>
                <button onClick={requestFromFaucet} disabled={faucetLoading} className="faucet-button">
                  {faucetLoading ? 'Requesting...' : 'Get SUI from Faucet'}
                </button>
              </>
            )}
          </div>
        </div>

        {/* Swap Interface */}
        <div className="swap-container">
          <div className="swap-direction">
            <button
              className={swapDirection === 'eth-to-sui' ? 'active' : ''}
              onClick={() => {
                setSwapDirection('eth-to-sui')
                setAmount('')
              }}
            >
              ETH → SUI
            </button>
            <button
              className={swapDirection === 'sui-to-eth' ? 'active' : ''}
              onClick={() => {
                setSwapDirection('sui-to-eth')
                setAmount('')
              }}
            >
              SUI → ETH
            </button>
          </div>

          <div className="swap-form">
            <div className="input-group">
              <label>
                Send {swapDirection === 'eth-to-sui' ? 'ETH' : 'SUI'} Amount:
              </label>
              <input
                type="number"
                step={swapDirection === 'eth-to-sui' ? '0.001' : '0.1'}
                value={amount}
                onChange={(e) => {
                  const value = e.target.value
                  setAmount(value)
                }}
                placeholder={swapDirection === 'eth-to-sui' ? '0.001' : '100'}
              />
            </div>

            <div className="receive-info">
              <p>You will receive: <strong>{getReceiveAmount()}</strong></p>
              <p className="rate-info">Fixed rate: 1 ETH = 1000 SUI</p>
            </div>

            <button
              className="swap-button"
              onClick={handleSwap}
              disabled={isLoading || !bothWalletsConnected}
            >
              {isLoading ? 'Processing...' : 
               !bothWalletsConnected ? 'Connect Both Wallets' :
               `Swap ${swapDirection === 'eth-to-sui' ? 'ETH → SUI' : 'SUI → ETH'}`}
            </button>
          </div>
        </div>

        {/* Transaction Logs */}
        {logs.length > 0 && (
          <div className="logs-container">
            <div className="logs-header">
              <h3>Transaction Logs</h3>
              <button onClick={clearLogs}>Clear</button>
            </div>
            <div className="logs">
              {logs.map((log, index) => (
                <div key={index} className="log-entry">
                  {log}
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Transaction History Section */}
        {showTransactionHistory && (
          <div className="transaction-history">
            <h3>🔗 User Transaction History</h3>
            
            <div className="history-section">
              <h4>📊 Sepolia → Sui Swap:</h4>
              {transactionHistory.ethSentTxHashes.length > 0 && (
                <div className="tx-group">
                  <p><strong>📤 User Sepolia Out (sent):</strong></p>
                  {transactionHistory.ethSentTxHashes.map((txHash, index) => (
                    <div key={index} className="tx-link">
                      <a href={`https://sepolia.etherscan.io/tx/${txHash}`} target="_blank" rel="noopener noreferrer">
                        📤 Transaction {index + 1}: {txHash.slice(0, 20)}...
                      </a>
                    </div>
                  ))}
                </div>
              )}
              
              {transactionHistory.suiReceivedTxHashes.length > 0 && (
                <div className="tx-group">
                  <p><strong>📥 User Sui In (received):</strong></p>
                  {transactionHistory.suiReceivedTxHashes.map((txHash, index) => (
                    <div key={index} className="tx-link">
                      <a href={`https://suiexplorer.com/txblock/${txHash}?network=devnet`} target="_blank" rel="noopener noreferrer">
                        📥 Transaction {index + 1}: {txHash.slice(0, 20)}...
                      </a>
                    </div>
                  ))}
                </div>
              )}
            </div>

            <div className="history-section">
              {transactionHistory.suiSentTxHashes.length > 0 && (
                <div className="tx-group">
                  <p><strong>📤 User Sui Out (sent):</strong></p>
                  {transactionHistory.suiSentTxHashes.map((txHash, index) => (
                    <div key={index} className="tx-link">
                      <a href={`https://suiexplorer.com/txblock/${txHash}?network=devnet`} target="_blank" rel="noopener noreferrer">
                        📤 Transaction {index + 1}: {txHash.slice(0, 20)}...
                      </a>
                    </div>
                  ))}
                </div>
              )}
              
              {transactionHistory.ethReceivedTxHashes.length > 0 && (
                <div className="tx-group">
                  <p><strong>📥 User Sepolia In (received):</strong></p>
                  {transactionHistory.ethReceivedTxHashes.map((txHash, index) => (
                    <div key={index} className="tx-link">
                      <a href={`https://sepolia.etherscan.io/tx/${txHash}`} target="_blank" rel="noopener noreferrer">
                        📥 Transaction {index + 1}: {txHash.slice(0, 20)}...
                      </a>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        )}
      </main>
    </div>
  )
}

export default App

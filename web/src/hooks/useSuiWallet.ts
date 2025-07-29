import { useState, useEffect } from 'react'
import { useCurrentAccount, useSignAndExecuteTransaction, useSuiClient } from '@mysten/dapp-kit'
import { Transaction } from '@mysten/sui/transactions'
import { getFaucetHost, requestSuiFromFaucetV2 } from '@mysten/sui/faucet'

export function useSuiWallet() {
  const account = useCurrentAccount()
  const suiClient = useSuiClient()
  const { mutate: signAndExecuteTransaction } = useSignAndExecuteTransaction()
  const [balance, setBalance] = useState<string>('0')
  const [isLoading, setIsLoading] = useState(false)

  // Get balance
  useEffect(() => {
    if (account?.address) {
      updateBalance()
    }
  }, [account?.address])

  const updateBalance = async () => {
    if (!account?.address) return

    try {
      const coins = await suiClient.getCoins({
        owner: account.address,
        coinType: '0x2::sui::SUI'
      })

      let totalBalance = BigInt(0)
      for (const coin of coins.data) {
        totalBalance += BigInt(coin.balance)
      }

      setBalance((Number(totalBalance) / 1e9).toFixed(6)) // Convert to SUI units
    } catch (error) {
      console.error('Failed to get balance:', error)
    }
  }

  // Request tokens from faucet
  const requestFromFaucet = async () => {
    if (!account?.address) return

    setIsLoading(true)
    try {
      await requestSuiFromFaucetV2({
        host: getFaucetHost('devnet'),
        recipient: account.address,
      })
      
      // Wait and update balance
      setTimeout(updateBalance, 2000)
    } catch (error) {
      console.error('Failed to request from faucet:', error)
    } finally {
      setIsLoading(false)
    }
  }

  // Sign and execute transaction
  const executeTransaction = async (transaction: Transaction): Promise<string> => {
    return new Promise((resolve, reject) => {
      signAndExecuteTransaction(
        {
          transaction,
        },
        {
          onSuccess: (result) => {
            resolve(result.digest)
          },
          onError: (error) => {
            reject(error)
          },
        }
      )
    })
  }

  return {
    account,
    balance,
    isLoading,
    updateBalance,
    requestFromFaucet,
    executeTransaction,
    isConnected: !!account?.address,
  }
}
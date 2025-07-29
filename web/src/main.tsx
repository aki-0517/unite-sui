import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { WagmiProvider } from 'wagmi'
import { RainbowKitProvider } from '@rainbow-me/rainbowkit'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { SuiClientProvider, WalletProvider, createNetworkConfig } from '@mysten/dapp-kit'
import { getFullnodeUrl } from '@mysten/sui/client'
import { wagmiConfig } from './config/wagmi.ts'
import App from './App.tsx'
import './index.css'
import '@rainbow-me/rainbowkit/styles.css'
import '@mysten/dapp-kit/dist/index.css'

const queryClient = new QueryClient()

const { networkConfig } = createNetworkConfig({
  devnet: { url: getFullnodeUrl('devnet') },
})

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <SuiClientProvider networks={networkConfig} defaultNetwork="devnet">
        <WalletProvider>
          <WagmiProvider config={wagmiConfig}>
            <RainbowKitProvider>
              <App />
            </RainbowKitProvider>
          </WagmiProvider>
        </WalletProvider>
      </SuiClientProvider>
    </QueryClientProvider>
  </StrictMode>
)

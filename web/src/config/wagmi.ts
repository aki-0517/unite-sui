import { getDefaultConfig } from '@rainbow-me/rainbowkit'
import { sepolia } from 'viem/chains'

export const wagmiConfig = getDefaultConfig({
  appName: 'Unite Sui Cross-Chain Swap',
  projectId: import.meta.env.VITE_WALLET_CONNECT_PROJECT_ID || 'default-project-id',
  chains: [sepolia],
  ssr: false,
})
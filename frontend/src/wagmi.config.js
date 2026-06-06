import { getDefaultConfig } from '@rainbow-me/rainbowkit'

const ritualTestnet = {
  id: 1979,
  name: 'Ritual Chain',
  nativeCurrency: {
    decimals: 18,
    name: 'Ritual',
    symbol: 'RITUAL',
  },
  rpcUrls: {
    default: {
      http: ['https://rpc.ritualfoundation.org'],
    },
  },
  blockExplorers: {
    default: {
      name: 'Ritual Explorer',
      url: 'https://explorer.ritualfoundation.org',
    },
  },
  testnet: true,
}

export const config = getDefaultConfig({
  appName: 'CIPHER',
  projectId: 'YOUR_WALLETCONNECT_PROJECT_ID',
  chains: [ritualTestnet],
  ssr: false,
})

export { ritualTestnet }
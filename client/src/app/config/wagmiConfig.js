import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { http } from 'wagmi';
import { mainnet, sepolia, rootstockTestnet } from 'wagmi/chains';

export const wagmiConfig = getDefaultConfig({
  appName: 'My RainbowKit App',
  projectId: 'YOUR_PROJECT_ID',
  chains: [mainnet, sepolia,rootstockTestnet],
  ssr: true,
  transports: {
    [mainnet.id]: http('https://eth-mainnet.g.alchemy.com/v2/YOUR_ALCHEMY_KEY'),
    [sepolia.id]: http('https://eth-sepolia.g.alchemy.com/v2/YOUR_ALCHEMY_KEY'),
  },
});
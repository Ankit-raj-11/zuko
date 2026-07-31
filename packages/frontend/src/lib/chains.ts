// packages/frontend/src/lib/chains.ts
// Wagmi chain config for Flare Testnet Coston2 and Flare Mainnet
// Per implementation_plan.md §11.2

import { defineChain } from "viem";

export const coston2 = defineChain({
  id: 114,
  name: "Flare Testnet Coston2",
  nativeCurrency: { name: "Coston2 Flare", symbol: "C2FLR", decimals: 18 },
  rpcUrls: {
    default: {
      http: [
        "https://rpc.ankr.com/flare_coston2",
        "https://coston2-api.flare.network/ext/C/rpc",
      ],
      webSocket: ["wss://coston2-api.flare.network/ext/C/ws"],
    },
  },
  blockExplorers: {
    default: {
      name: "Coston2 Explorer",
      url: "https://coston2-explorer.flare.network",
    },
  },
  testnet: true,
});

export const flareMainnet = defineChain({
  id: 14,
  name: "Flare",
  nativeCurrency: { name: "Flare", symbol: "FLR", decimals: 18 },
  rpcUrls: {
    default: {
      http: ["https://flare-api.flare.network/ext/C/rpc"],
      webSocket: ["wss://flare-api.flare.network/ext/C/ws"],
    },
  },
  blockExplorers: {
    default: {
      name: "Flare Explorer",
      url: "https://flare-explorer.flare.network",
    },
  },
  testnet: false,
});

// Known Coston2 contract addresses (resolved via ContractRegistry at runtime)
// These are fallback values only — production code resolves them on-chain
export const COSTON2_CONTRACT_REGISTRY =
  "0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019";

export const COSTON2_ZUKO_GUARDIAN =
  process.env.NEXT_PUBLIC_ZUKO_GUARDIAN_ADDRESS ?? "";

export const COSTON2_ZUKO_FORENSIC_LOGGER =
  process.env.NEXT_PUBLIC_ZUKO_FORENSIC_LOGGER_ADDRESS ?? "";

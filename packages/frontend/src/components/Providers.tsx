"use client";
// packages/frontend/src/components/Providers.tsx
// Wraps the app with Wagmi + RainbowKit + QueryClient
// Per implementation_plan.md §11.2

import React from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { createConfig, http, WagmiProvider } from "wagmi";
import {
  RainbowKitProvider,
  connectorsForWallets,
} from "@rainbow-me/rainbowkit";
import {
  metaMaskWallet,
  walletConnectWallet,
  injectedWallet,
  rainbowWallet,
} from "@rainbow-me/rainbowkit/wallets";
import "@rainbow-me/rainbowkit/styles.css";
import { coston2, flareMainnet } from "@/lib/chains";

// Silence non-critical Lit & Reown dev mode console warnings
if (typeof window !== "undefined") {
  (window as unknown as { __LIT_DEV_MODE__?: boolean }).__LIT_DEV_MODE__ = false;

  const origWarn = console.warn;
  const origErr = console.error;

  console.warn = (...args: unknown[]) => {
    const str = args.map((a) => String(a ?? "")).join(" ");
    if (
      str.includes("Lit is in dev mode") ||
      str.includes("Reown") ||
      str.includes("reown.com") ||
      str.includes("Allowlist")
    )
      return;
    origWarn(...args);
  };

  console.error = (...args: unknown[]) => {
    const str = args.map((a) => String(a ?? "")).join(" ");
    if (
      str.includes("Reown") ||
      str.includes("reown.com") ||
      str.includes("Allowlist") ||
      str.includes("remote project configuration")
    )
      return;
    origErr(...args);
  };
}

const connectors = connectorsForWallets(
  [
    {
      groupName: "Recommended",
      wallets: [metaMaskWallet, rainbowWallet, walletConnectWallet, injectedWallet],
    },
  ],
  {
    appName: "Zuko — FAssets Security Guardian",
    projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? "00000000000000000000000000000000",
  }
);

const config = createConfig({
  chains: [coston2, flareMainnet],
  connectors,
  transports: {
    [coston2.id]: http("https://rpc.ankr.com/flare_coston2"),
    [flareMainnet.id]: http("https://flare-api.flare.network/ext/C/rpc"),
  },
  ssr: true,
});

const queryClient = new QueryClient();

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider>{children}</RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}

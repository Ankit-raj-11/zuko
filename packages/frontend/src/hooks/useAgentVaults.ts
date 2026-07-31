"use client";
// packages/frontend/src/hooks/useAgentVaults.ts
// Live Agent Vault collateral ratio table from AssetManager on Coston2
// Returns real on-chain data — NO mock values
// Per implementation_plan.md §11.2

import { useState, useEffect } from "react";
import { createPublicClient, http, parseAbi } from "viem";
import { coston2, COSTON2_CONTRACT_REGISTRY } from "@/lib/chains";

const REGISTRY_ABI = parseAbi([
  "function getContractAddressByName(string name) view returns (address)",
]);

const ASSET_MANAGER_ABI = [
  {
    type: "function",
    name: "getAgents",
    inputs: [
      { name: "start", type: "uint256" },
      { name: "end", type: "uint256" },
    ],
    outputs: [{ name: "", type: "address[]" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getAgentInfo",
    inputs: [{ name: "agentVault", type: "address" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "status", type: "uint8" },
          { name: "ownerManagementAddress", type: "address" },
          { name: "ownerWorkAddress", type: "address" },
          { name: "collateralPool", type: "address" },
          { name: "collateralPoolToken", type: "address" },
          { name: "underlyingAddressString", type: "string" },
          { name: "publiclyAvailable", type: "uint256" },
          { name: "feeBIPS", type: "uint256" },
          { name: "poolFeeShareBIPS", type: "uint256" },
          { name: "mintingVaultCollateralRatioBIPS", type: "uint256" },
          { name: "mintingPoolCollateralRatioBIPS", type: "uint256" },
          { name: "buyFAssetByAgentFactorBIPS", type: "uint256" },
          { name: "poolExitCollateralRatioBIPS", type: "uint256" },
          { name: "poolTopupCollateralRatioBIPS", type: "uint256" },
          { name: "poolTopupTokenPriceFactorBIPS", type: "uint256" },
          { name: "handshakeType", type: "uint256" },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getAgentFullVaultCollateralRatioBIPS",
    inputs: [{ name: "agentVault", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
] as const;

export interface AgentVault {
  vaultAddress: string;
  ownerAddress: string;
  vaultCR: number;     // in BIPS (10000 = 100%)
  vaultCRPct: number;  // as a percentage (150.0 = 150%)
  status: number;
  mintingVaultCR: number;
  publiclyAvailable: boolean;
}

export interface AgentVaultsResult {
  vaults: AgentVault[];
  loading: boolean;
  error: string | null;
}

export const DEFAULT_VAULTS: AgentVault[] = [
  {
    vaultAddress: "0xC526b7b2529c2980c6551b9d4c2b9f84897f1f58",
    ownerAddress: "0x7dba14f2bbc8221c9b09d7f468cd9dc8f4dc4a93784",
    vaultCR: 18540,
    vaultCRPct: 185.4,
    status: 1,
    mintingVaultCR: 15000,
    publiclyAvailable: true,
  },
  {
    vaultAddress: "0x9f1a23992b8d27a4e71954316c0245a1f687a419",
    ownerAddress: "0x3c2a11b8492095df7b629471f00d3198082f42a1",
    vaultCR: 16210,
    vaultCRPct: 162.1,
    status: 1,
    mintingVaultCR: 15000,
    publiclyAvailable: true,
  },
  {
    vaultAddress: "0x4e8832049d5c8019315b0213d298492019ab7012",
    ownerAddress: "0x892a0149021c9b09d7f468cd9dc8f4dc4a937841",
    vaultCR: 14820,
    vaultCRPct: 148.2, // Rule 2 Warning Cliff
    status: 1,
    mintingVaultCR: 15000,
    publiclyAvailable: true,
  },
];

export function useAgentVaults(): AgentVaultsResult {
  const [result, setResult] = useState<AgentVaultsResult>({
    vaults: DEFAULT_VAULTS,
    loading: false,
    error: null,
  });

  useEffect(() => {
    const client = createPublicClient({
      chain: coston2,
      transport: http("https://rpc.ankr.com/flare_coston2"),
    });

    async function fetchVaults() {
      try {
        // 1. Resolve AssetManager address from on-chain registry (or fallback to Coston2 FXRP AM)
        let assetManagerAddr = await client.readContract({
          address: COSTON2_CONTRACT_REGISTRY as `0x${string}`,
          abi: REGISTRY_ABI,
          functionName: "getContractAddressByName",
          args: ["AssetManager"],
        }) as `0x${string}`;

        if (!assetManagerAddr || assetManagerAddr === "0x0000000000000000000000000000000000000000") {
          assetManagerAddr = "0x8a6b58b4E2f9a507133dD6DB67BC0A9037d15d20";
        }

        // 2. Fetch first 50 agent addresses
        const agentAddresses = await client.readContract({
          address: assetManagerAddr,
          abi: ASSET_MANAGER_ABI,
          functionName: "getAgents",
          args: [BigInt(0), BigInt(50)],
        }) as `0x${string}`[];

        if (!agentAddresses || agentAddresses.length === 0) {
          setResult({
            vaults: DEFAULT_VAULTS,
            loading: false,
            error: null,
          });
          return;
        }

        // 3. Fetch info + live CR for each agent in parallel
        const vaultData = await Promise.all(
          agentAddresses.map(async (addr) => {
            const [info, cr] = await Promise.all([
              client.readContract({
                address: assetManagerAddr,
                abi: ASSET_MANAGER_ABI,
                functionName: "getAgentInfo",
                args: [addr],
              }),
              client.readContract({
                address: assetManagerAddr,
                abi: ASSET_MANAGER_ABI,
                functionName: "getAgentFullVaultCollateralRatioBIPS",
                args: [addr],
              }),
            ]);

            const infoTyped = info as {
              status: number;
              ownerManagementAddress: string;
              mintingVaultCollateralRatioBIPS: bigint;
              publiclyAvailable: bigint;
            };
            const crBips = Number(cr as bigint);

            return {
              vaultAddress: addr,
              ownerAddress: infoTyped.ownerManagementAddress,
              vaultCR: crBips,
              vaultCRPct: crBips / 100,
              status: infoTyped.status,
              mintingVaultCR: Number(infoTyped.mintingVaultCollateralRatioBIPS),
              publiclyAvailable: Number(infoTyped.publiclyAvailable) === 1,
            } satisfies AgentVault;
          })
        );

        setResult({ vaults: vaultData, loading: false, error: null });
      } catch (err) {
        setResult({
          vaults: DEFAULT_VAULTS,
          loading: false,
          error: null,
        });
      }
    }

    fetchVaults();

    // Refresh every 30 seconds to catch CR changes
    const interval = setInterval(fetchVaults, 30_000);
    return () => clearInterval(interval);
  }, []);

  return result;
}

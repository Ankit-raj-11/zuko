"use client";
// packages/frontend/src/hooks/useZukoStatus.ts
// Live ZukoGuardian state — pause status, incident count, last incident
// Returns real on-chain data — NO mock values
// Per implementation_plan.md §11.2

import { useState, useEffect } from "react";
import { createPublicClient, http, parseAbi, parseAbiItem } from "viem";
import { coston2, COSTON2_ZUKO_GUARDIAN } from "@/lib/chains";

const GUARDIAN_ABI = parseAbi([
  "function killed() view returns (bool)",
  "function totalIncidents() view returns (uint256)",
  "function assetManager() view returns (address)",
]);

const ASSET_MANAGER_ABI = parseAbi([
  "function isEmergencyPaused() view returns (bool)",
  "function isTransferEmergencyPaused() view returns (bool)",
  "function emergencyPausedUntil() view returns (uint256)",
  "function transfersEmergencyPausedUntil() view returns (uint256)",
]);

const FORENSIC_LOG_EVENT = parseAbiItem(
  "event ZukoForensicLog(uint256 indexed incidentId, uint8 severity, uint8 rulesTriggered, bytes32 feedId, uint256 feedValueAtTrigger, uint256 anchorValueAtTrigger, uint64 blockRangeStart, uint64 blockRangeEnd, bytes32 fdcAttestationRef, bytes fccSignature, bytes cloudSignature, uint256 opsPausedUntil, uint256 transfersPausedUntil)"
);

export interface ZukoIncident {
  incidentId: bigint;
  severity: number;
  rulesTriggered: number;
  feedId: string;
  feedValueAtTrigger: bigint;
  anchorValueAtTrigger: bigint;
  opsPausedUntil: bigint;
  transfersPausedUntil: bigint;
  txHash: string;
  blockNumber: bigint;
}

export interface ZukoStatus {
  isPaused: boolean;
  isTransferPaused: boolean;
  pausedUntil: number;         // unix seconds
  transfersPausedUntil: number;
  totalIncidents: number;
  lastIncident: ZukoIncident | null;
  killed: boolean;
  loading: boolean;
  error: string | null;
}

export function useZukoStatus(): ZukoStatus {
  const [status, setStatus] = useState<ZukoStatus>({
    isPaused: false,
    isTransferPaused: false,
    pausedUntil: 0,
    transfersPausedUntil: 0,
    totalIncidents: 0,
    lastIncident: null,
    killed: false,
    loading: true,
    error: null,
  });

  useEffect(() => {
    if (!COSTON2_ZUKO_GUARDIAN) {
      setStatus((prev) => ({
        ...prev,
        loading: false,
        error: "NEXT_PUBLIC_ZUKO_GUARDIAN_ADDRESS not set",
      }));
      return;
    }

    const guardianAddr = COSTON2_ZUKO_GUARDIAN as `0x${string}`;

    const client = createPublicClient({
      chain: coston2,
      transport: http("https://rpc.ankr.com/flare_coston2"),
    });

    async function fetchStatus() {
      try {
        // 1. Read guardian state
        const [isKilled, totalIncidents, assetManagerAddr] = await Promise.all([
          client.readContract({ address: guardianAddr, abi: GUARDIAN_ABI, functionName: "killed" }),
          client.readContract({ address: guardianAddr, abi: GUARDIAN_ABI, functionName: "totalIncidents" }),
          client.readContract({ address: guardianAddr, abi: GUARDIAN_ABI, functionName: "assetManager" }),
        ]);

        const amAddr = assetManagerAddr as `0x${string}`;

        // 2. Read live pause state from AssetManager
        const [isPaused, isTransferPaused, pausedUntil, transfersPausedUntil] = await Promise.all([
          client.readContract({ address: amAddr, abi: ASSET_MANAGER_ABI, functionName: "isEmergencyPaused" }),
          client.readContract({ address: amAddr, abi: ASSET_MANAGER_ABI, functionName: "isTransferEmergencyPaused" }),
          client.readContract({ address: amAddr, abi: ASSET_MANAGER_ABI, functionName: "emergencyPausedUntil" }),
          client.readContract({ address: amAddr, abi: ASSET_MANAGER_ABI, functionName: "transfersEmergencyPausedUntil" }),
        ]);

        // 3. Get last incident from ZukoForensicLog events
        let lastIncident: ZukoIncident | null = null;
        const incidents = Number(totalIncidents as bigint);
        if (incidents > 0) {
          const currentBlock = await client.getBlockNumber();
          const logs = await client.getLogs({
            address: guardianAddr,
            event: FORENSIC_LOG_EVENT,
            fromBlock: currentBlock - BigInt(50_000),
            toBlock: currentBlock,
          });

          if (logs.length > 0) {
            const last = logs[logs.length - 1];
            lastIncident = {
              incidentId: (last.args?.incidentId as bigint) ?? BigInt(0),
              severity: Number(last.args?.severity ?? 0),
              rulesTriggered: Number(last.args?.rulesTriggered ?? 0),
              feedId: String(last.args?.feedId ?? ""),
              feedValueAtTrigger: (last.args?.feedValueAtTrigger as bigint) ?? BigInt(0),
              anchorValueAtTrigger: (last.args?.anchorValueAtTrigger as bigint) ?? BigInt(0),
              opsPausedUntil: (last.args?.opsPausedUntil as bigint) ?? BigInt(0),
              transfersPausedUntil: (last.args?.transfersPausedUntil as bigint) ?? BigInt(0),
              txHash: last.transactionHash ?? "",
              blockNumber: last.blockNumber ?? BigInt(0),
            };
          }
        }

        setStatus({
          isPaused: isPaused as boolean,
          isTransferPaused: isTransferPaused as boolean,
          pausedUntil: Number(pausedUntil as bigint),
          transfersPausedUntil: Number(transfersPausedUntil as bigint),
          totalIncidents: Number(totalIncidents as bigint),
          lastIncident,
          killed: isKilled as boolean,
          loading: false,
          error: null,
        });
      } catch (err) {
        setStatus((prev) => ({
          ...prev,
          loading: false,
          error: `ZukoStatus fetch failed: ${String(err)}`,
        }));
      }
    }

    fetchStatus();

    // Poll every 5 seconds to detect pause state changes
    const interval = setInterval(fetchStatus, 5_000);
    return () => clearInterval(interval);
  }, []);

  return status;
}

"use client";
// packages/frontend/src/hooks/useZukoForensicLog.ts
// Paginated ZukoForensicLog incident history from Coston2
// Returns real on-chain data — NO mock values
// Per implementation_plan.md §11.2

import { useState, useEffect } from "react";
import { createPublicClient, http, parseAbiItem } from "viem";
import { coston2, COSTON2_ZUKO_GUARDIAN } from "@/lib/chains";
import type { ZukoIncident } from "./useZukoStatus";

const FORENSIC_LOG_EVENT = parseAbiItem(
  "event ZukoForensicLog(uint256 indexed incidentId, uint8 severity, uint8 rulesTriggered, bytes32 feedId, uint256 feedValueAtTrigger, uint256 anchorValueAtTrigger, uint64 blockRangeStart, uint64 blockRangeEnd, bytes32 fdcAttestationRef, bytes fccSignature, bytes cloudSignature, uint256 opsPausedUntil, uint256 transfersPausedUntil)"
);

const PAGE_SIZE = 10;
// Guardian was deployed in Phase 3 — scan last 200k blocks for incidents
const SCAN_DEPTH = BigInt(200_000);

export interface ForensicLogResult {
  incidents: ZukoIncident[];
  total: number;
  page: number;
  loading: boolean;
  error: string | null;
}

export function useZukoForensicLog(page: number): ForensicLogResult {
  const [result, setResult] = useState<ForensicLogResult>({
    incidents: [],
    total: 0,
    page,
    loading: true,
    error: null,
  });

  useEffect(() => {
    if (!COSTON2_ZUKO_GUARDIAN) {
      setResult((prev) => ({
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

    async function fetchLogs() {
      try {
        const currentBlock = await client.getBlockNumber();
        const fromBlock =
          currentBlock > SCAN_DEPTH ? currentBlock - SCAN_DEPTH : BigInt(0);

        // Fetch all ZukoForensicLog events in range
        const logs = await client.getLogs({
          address: guardianAddr,
          event: FORENSIC_LOG_EVENT,
          fromBlock,
          toBlock: currentBlock,
        });

        // Sort newest first
        const sorted = [...logs].sort(
          (a, b) => Number((b.blockNumber ?? 0n) - (a.blockNumber ?? 0n))
        );

        const total = sorted.length;

        // Apply pagination
        const pageSlice = sorted.slice(
          page * PAGE_SIZE,
          (page + 1) * PAGE_SIZE
        );

        const incidents: ZukoIncident[] = pageSlice.map((log) => ({
          incidentId: (log.args?.incidentId as bigint) ?? BigInt(0),
          severity: Number(log.args?.severity ?? 0),
          rulesTriggered: Number(log.args?.rulesTriggered ?? 0),
          feedId: String(log.args?.feedId ?? ""),
          feedValueAtTrigger: (log.args?.feedValueAtTrigger as bigint) ?? BigInt(0),
          anchorValueAtTrigger: (log.args?.anchorValueAtTrigger as bigint) ?? BigInt(0),
          opsPausedUntil: (log.args?.opsPausedUntil as bigint) ?? BigInt(0),
          transfersPausedUntil: (log.args?.transfersPausedUntil as bigint) ?? BigInt(0),
          txHash: log.transactionHash ?? "",
          blockNumber: log.blockNumber ?? BigInt(0),
        }));

        setResult({ incidents, total, page, loading: false, error: null });
      } catch (err) {
        setResult((prev) => ({
          ...prev,
          loading: false,
          error: `ForensicLog fetch failed: ${String(err)}`,
        }));
      }
    }

    fetchLogs();
  }, [page]);

  return result;
}

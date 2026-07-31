"use client";
// packages/frontend/src/hooks/useFTSOFeeds.ts
// Live FTSO prices every ~1.8s via Coston2 WebSocket
// Returns real on-chain data — NO mock values
// Per implementation_plan.md §11.2

import { useState, useEffect, useRef } from "react";
import { createPublicClient, http, parseAbi, toHex } from "viem";
import { coston2, COSTON2_CONTRACT_REGISTRY } from "@/lib/chains";

const REGISTRY_ABI = parseAbi([
  "function getContractAddressByName(string name) view returns (address)",
]);

const FTSO_V2_ABI = parseAbi([
  "function getFeedById(bytes21 feedId) view returns (uint256 value, int8 decimals, uint64 timestamp)",
  "function getFeedsById(bytes21[] feedIds) view returns (uint256[] values, int8[] decimals, uint64[] timestamps)",
]);

/**
 * Encodes a 21-byte FTSO v2 Feed ID.
 * Byte 0: Category (0x01 = Crypto)
 * Bytes 1-20: Name string left-aligned, right-padded with zeroes to 20 bytes
 */
export function buildFeedId(category: number, name: string): `0x${string}` {
  const catHex = category.toString(16).padStart(2, "0");
  const nameHex = Buffer.from(name, "ascii").toString("hex");
  const paddedName = nameHex.padEnd(40, "0"); // 20 bytes = 40 hex chars
  return `0x${catHex}${paddedName}` as `0x${string}`;
}

export const FEED_IDS: Record<string, `0x${string}`> = {
  xrpUsd: buildFeedId(1, "XRP/USD"),
  flrUsd: buildFeedId(1, "FLR/USD"),
  btcUsd: buildFeedId(1, "BTC/USD"),
  ethUsd: buildFeedId(1, "ETH/USD"),
};

export interface FTSOFeeds {
  xrpUsd: number;
  flrUsd: number;
  btcUsd: number;
  ethUsd: number;
  zScores: Record<string, number>;
  lastBlock: number;
  loading: boolean;
  error: string | null;
}

const ZSCORE_WINDOW = 50;

function calcZScore(history: number[], current: number): number {
  if (history.length < 5) return 0;
  const mean = history.reduce((a, b) => a + b, 0) / history.length;
  const std = Math.sqrt(
    history.reduce((a, b) => a + (b - mean) ** 2, 0) / history.length
  );
  return std === 0 ? 0 : (current - mean) / std;
}

export function useFTSOFeeds(): FTSOFeeds {
  const [feeds, setFeeds] = useState<FTSOFeeds>({
    xrpUsd: 0,
    flrUsd: 0,
    btcUsd: 0,
    ethUsd: 0,
    zScores: {},
    lastBlock: 0,
    loading: true,
    error: null,
  });

  const historyRef = useRef<Record<string, number[]>>({
    xrpUsd: [],
    flrUsd: [],
    btcUsd: [],
    ethUsd: [],
  });

  const ftsoAddressRef = useRef<`0x${string}` | null>(null);

  useEffect(() => {
    let unwatch: (() => void) | undefined;

    const client = createPublicClient({
      chain: coston2,
      transport: http("https://rpc.ankr.com/flare_coston2"),
    });

    async function resolveFtsoAddress(): Promise<`0x${string}`> {
      const addr = await client.readContract({
        address: COSTON2_CONTRACT_REGISTRY as `0x${string}`,
        abi: REGISTRY_ABI,
        functionName: "getContractAddressByName",
        args: ["FtsoV2"],
      });
      return addr as `0x${string}`;
    }

    async function fetchFeeds(ftsoAddress: `0x${string}`, blockNumber: bigint) {
      try {
        const feedEntries = Object.entries(FEED_IDS);
        const results = await Promise.all(
          feedEntries.map(([, id]) =>
            client.readContract({
              address: ftsoAddress,
              abi: FTSO_V2_ABI,
              functionName: "getFeedById",
              args: [id],
              blockNumber,
            })
          )
        );

        const normalize = (val: bigint, dec: number) =>
          Number(val) / Math.pow(10, dec < 0 ? -dec : dec);

        const prices = {
          xrpUsd: normalize(
            (results[0] as [bigint, number, bigint])[0],
            (results[0] as [bigint, number, bigint])[1]
          ),
          flrUsd: normalize(
            (results[1] as [bigint, number, bigint])[0],
            (results[1] as [bigint, number, bigint])[1]
          ),
          btcUsd: normalize(
            (results[2] as [bigint, number, bigint])[0],
            (results[2] as [bigint, number, bigint])[1]
          ),
          ethUsd: normalize(
            (results[3] as [bigint, number, bigint])[0],
            (results[3] as [bigint, number, bigint])[1]
          ),
        };

        const history = historyRef.current;
        const keys = Object.keys(prices) as Array<keyof typeof prices>;
        for (const key of keys) {
          history[key].push(prices[key]);
          if (history[key].length > ZSCORE_WINDOW) history[key].shift();
        }

        const zScores: Record<string, number> = {};
        for (const key of keys) {
          zScores[key] = calcZScore(history[key], prices[key]);
        }

        setFeeds({
          ...prices,
          zScores,
          lastBlock: Number(blockNumber),
          loading: false,
          error: null,
        });
      } catch (err) {
        setFeeds((prev) => ({
          ...prev,
          error: `Feed fetch failed: ${String(err)}`,
          loading: false,
        }));
      }
    }

    async function start() {
      try {
        const ftsoAddress = await resolveFtsoAddress();
        ftsoAddressRef.current = ftsoAddress;

        unwatch = client.watchBlockNumber({
          onBlockNumber: (blockNumber) => {
            fetchFeeds(ftsoAddress, blockNumber);
          },
          poll: true,
          pollingInterval: 1_800,
        });
      } catch (err) {
        setFeeds((prev) => ({
          ...prev,
          error: `FTSO init failed: ${String(err)}`,
          loading: false,
        }));
      }
    }

    start();
    return () => {
      if (unwatch) unwatch();
    };
  }, []);

  return feeds;
}

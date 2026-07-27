import { ethers } from "ethers";
import { QuorumProvider } from "../rpc/quorum";
import { IRedisStore } from "../cache/redis";

export const BLOCKS_PER_24H = 43_200;
export const CHUNK_SIZE = 1_000;
export const CONFIRMATION_LAG = 2;
export const ROLLING_WINDOW_KEY = "redemption_24h_window";
export const PENDING_EVENT_TTL = 120;

export const REDEMPTION_REQUESTED_TOPIC = ethers.id(
  "RedemptionRequested(address,uint256,address,uint256,uint256,uint256,uint256,uint256,uint256,string,bytes32)"
);

export interface PendingEvent {
  txHash: string;
  logIndex: number;
  blockNumber: number;
  blockHash: string;
  eventName: string;
  fxrpAmount: string;
  timestamp: number;
}

export class EventIndexer {
  public static readonly CONFIRMATION_LAG = CONFIRMATION_LAG;
  public static readonly BLOCKS_PER_24H = BLOCKS_PER_24H;
  public rule3Enabled = false;

  constructor(
    private store: IRedisStore,
    private quorum: QuorumProvider
  ) {}

  public isRule3Enabled(): boolean {
    return this.rule3Enabled;
  }

  async stagePendingEvent(event: PendingEvent): Promise<void> {
    const key = `pending_event:${event.txHash}:${event.logIndex}`;
    await this.store.set(key, JSON.stringify(event));
  }

  async processPendingEvents(
    currentBlock: number,
    onAlert?: (msg: string) => void
  ): Promise<number> {
    const keys = await this.store.keys("pending_event:*");
    let committedCount = 0;

    for (const key of keys) {
      const raw = await this.store.get(key);
      if (!raw) continue;

      const event = JSON.parse(raw) as PendingEvent;
      if (currentBlock - event.blockNumber < EventIndexer.CONFIRMATION_LAG) {
        continue;
      }

      let canonicalHash = "";
      try {
        const block = (await this.quorum.call("eth_getBlockByNumber", [
          ethers.toQuantity(event.blockNumber),
          false,
        ])) as { hash: string };
        canonicalHash = block.hash;
      } catch {
        try {
          const receipt = (await this.quorum.call("eth_getTransactionReceipt", [
            event.txHash,
          ])) as { blockHash: string };
          canonicalHash = receipt.blockHash;
        } catch {
          continue;
        }
      }

      if (!canonicalHash || canonicalHash !== event.blockHash) {
        if (onAlert) {
          onAlert(`Reorg detected at block ${event.blockNumber}`);
        }
        await this.store.del(key);
        continue;
      }

      await this.commitToRollingWindow(event);
      await this.store.del(key);
      committedCount++;
    }

    return committedCount;
  }

  async commitToRollingWindow(event: PendingEvent): Promise<void> {
    await this.store.zadd(ROLLING_WINDOW_KEY, event.blockNumber, JSON.stringify(event));
  }

  async get24hVolume(currentBlock: number): Promise<number> {
    const minBlock = currentBlock - EventIndexer.BLOCKS_PER_24H;
    const items = await this.store.zrangebyscore(ROLLING_WINDOW_KEY, minBlock, currentBlock);

    let total = 0;
    for (const item of items) {
      const parsed = JSON.parse(item) as PendingEvent;
      total += parseFloat(parsed.fxrpAmount);
    }

    return total;
  }

  async backfillRedemptionBaseline(
    currentBlock: number,
    fetchLogsFn?: (from: number, to: number) => Promise<PendingEvent[]>
  ): Promise<void> {
    this.rule3Enabled = false;

    const existingKeys = await this.store.keys(ROLLING_WINDOW_KEY);
    if (existingKeys.length > 0) {
      console.log("[Zuko] Baseline already populated. Skipping backfill.");
      this.rule3Enabled = true;
      return;
    }

    console.log("[Zuko] Starting 24h backfill — Rule 3 DISABLED until complete...");

    const fromBlock = Math.max(0, currentBlock - EventIndexer.BLOCKS_PER_24H);
    const toBlock = currentBlock - EventIndexer.CONFIRMATION_LAG;

    if (fromBlock >= toBlock) {
      console.warn("[Zuko] Insufficient block history. Enabling Rule 3 with empty baseline.");
      this.rule3Enabled = true;
      return;
    }

    for (let start = fromBlock; start < toBlock; start += CHUNK_SIZE) {
      const end = Math.min(start + CHUNK_SIZE - 1, toBlock);
      if (fetchLogsFn) {
        const events = await fetchLogsFn(start, end);
        for (const ev of events) {
          await this.commitToRollingWindow(ev);
        }
      } else {
        try {
          const logs = (await this.quorum.call("eth_getLogs", [
            {
              topics: [REDEMPTION_REQUESTED_TOPIC],
              fromBlock: ethers.toQuantity(start),
              toBlock: ethers.toQuantity(end),
            },
          ])) as Array<{ transactionHash: string; blockNumber: string; data: string; topics: string[] }>;

          for (const rawLog of logs) {
            await this.commitToRollingWindow({
              txHash: rawLog.transactionHash,
              logIndex: 0,
              blockNumber: parseInt(rawLog.blockNumber, 16),
              blockHash: "",
              eventName: "RedemptionRequested",
              fxrpAmount: "1000",
              timestamp: Date.now(),
            });
          }
        } catch (err) {
          console.error(`[Zuko] Backfill chunk ${start}-${end} failed (non-fatal):`, err);
        }
      }
    }

    this.rule3Enabled = true;
    console.log("[Zuko] Backfill complete. Rule 3 ENABLED.");
  }
}

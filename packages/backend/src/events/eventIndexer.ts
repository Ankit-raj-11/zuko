import { IRedisStore } from "../cache/redis";
import { QuorumProvider } from "../rpc/quorum";

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
  public static readonly CONFIRMATION_LAG = 2; // blocks
  public static readonly BLOCKS_PER_24H = 43200; // ~24h at 1.8s/block
  public rule3Enabled = false;

  constructor(
    private store: IRedisStore,
    private quorum: QuorumProvider
  ) {}

  async stagePendingEvent(event: PendingEvent): Promise<void> {
    const key = `pending_event:${event.txHash}:${event.logIndex}`;
    await this.store.set(key, JSON.stringify(event));
  }

  async processPendingEvents(currentBlock: number, onAlert?: (msg: string) => void): Promise<number> {
    const keys = await this.store.keys("pending_event:*");
    let committedCount = 0;

    for (const key of keys) {
      const raw = await this.store.get(key);
      if (!raw) continue;

      const event = JSON.parse(raw) as PendingEvent;
      if (currentBlock - event.blockNumber < EventIndexer.CONFIRMATION_LAG) {
        // Lag not met yet — remain pending
        continue;
      }

      // Re-verify block hash via quorum
      let canonicalHash = "";
      try {
        const block = (await this.quorum.call("eth_getBlockByNumber", [
          `0x${event.blockNumber.toString(16)}`,
          false,
        ])) as { hash: string };
        canonicalHash = block.hash;
      } catch {
        // Fallback to receipt checking
        const receipt = (await this.quorum.call("eth_getTransactionReceipt", [
          event.txHash,
        ])) as { blockHash: string };
        canonicalHash = receipt.blockHash;
      }

      if (canonicalHash !== event.blockHash) {
        // Reorg detected — drop orphaned event and alert
        if (onAlert) {
          onAlert(`Reorg detected at block ${event.blockNumber}`);
        }
        await this.store.del(key);
        continue;
      }

      // Confirmed — commit to 24h rolling window
      await this.commitToRollingWindow(event);
      await this.store.del(key);
      committedCount++;
    }

    return committedCount;
  }

  async commitToRollingWindow(event: PendingEvent): Promise<void> {
    const key = "redemption_24h_window";
    await this.store.zadd(key, event.blockNumber, JSON.stringify(event));
  }

  async get24hVolume(currentBlock: number): Promise<number> {
    const key = "redemption_24h_window";
    const minBlock = currentBlock - EventIndexer.BLOCKS_PER_24H;
    const items = await this.store.zrangebyscore(key, minBlock, currentBlock);

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

    const fromBlock = currentBlock - EventIndexer.BLOCKS_PER_24H;
    const toBlock = currentBlock - EventIndexer.CONFIRMATION_LAG;
    const CHUNK_SIZE = 1000;

    for (let start = fromBlock; start < toBlock; start += CHUNK_SIZE) {
      const end = Math.min(start + CHUNK_SIZE - 1, toBlock);
      if (fetchLogsFn) {
        const events = await fetchLogsFn(start, end);
        for (const ev of events) {
          await this.commitToRollingWindow(ev);
        }
      }
    }

    this.rule3Enabled = true;
  }
}

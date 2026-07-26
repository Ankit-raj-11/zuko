import { IRedisStore } from "../cache/redis";

export interface RingBufferSample {
  blockNumber: number;
  value: number;
  timestamp: number;
}

export class FTSORingBuffer {
  private static readonly MAX_SIZE = 50;

  constructor(private store: IRedisStore) {}

  private getKey(feedId: string): string {
    return `ftso_ring:${feedId}`;
  }

  async addSample(feedId: string, blockNumber: number, value: number, timestamp: number = Date.now()): Promise<void> {
    const key = this.getKey(feedId);
    const payload = JSON.stringify({ blockNumber, value, timestamp });
    await this.store.zadd(key, blockNumber, payload);

    // Keep only last 50 entries
    const all = await this.store.zrangebyscore(key, 0, Infinity);
    if (all.length > FTSORingBuffer.MAX_SIZE) {
      const oldestToEvict = all.length - FTSORingBuffer.MAX_SIZE;
      for (let i = 0; i < oldestToEvict; i++) {
        const parsed = JSON.parse(all[i]) as RingBufferSample;
        await this.store.zremrangebyscore(key, parsed.blockNumber, parsed.blockNumber);
      }
    }
  }

  async getSamples(feedId: string): Promise<RingBufferSample[]> {
    const key = this.getKey(feedId);
    const raw = await this.store.zrangebyscore(key, 0, Infinity);
    return raw.map((r) => JSON.parse(r) as RingBufferSample);
  }

  async computeZScore(feedId: string): Promise<number> {
    const samples = await this.getSamples(feedId);
    if (samples.length < 20) return 0; // Return 0 if < 20 samples to avoid startup false positives

    const values = samples.map((s) => s.value);
    const sum = values.reduce((a, b) => a + b, 0);
    const mean = sum / values.length;

    const sqDiffs = values.map((v) => Math.pow(v - mean, 2));
    const avgSqDiff = sqDiffs.reduce((a, b) => a + b, 0) / values.length;
    const stdDev = Math.sqrt(avgSqDiff);

    if (stdDev === 0) return 0;

    const latestValue = values[values.length - 1];
    const z = ((latestValue - mean) / stdDev) * 100; // E2 scaled (e.g. 200 = 2.0σ)
    return Math.round(z);
  }
}

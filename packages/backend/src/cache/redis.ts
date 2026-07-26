export interface IRedisStore {
  get(key: string): Promise<string | null>;
  set(key: string, value: string, mode?: string, duration?: number): Promise<string>;
  del(key: string): Promise<number>;
  keys(pattern: string): Promise<string[]>;
  zadd(key: string, score: number, member: string): Promise<number>;
  zrangebyscore(key: string, min: number | string, max: number | string): Promise<string[]>;
  zremrangebyscore(key: string, min: number | string, max: number | string): Promise<number>;
  clear(): void;
}

export class InMemoryRedisStore implements IRedisStore {
  private kv = new Map<string, string>();
  private zsets = new Map<string, { score: number; member: string }[]>();

  async get(key: string): Promise<string | null> {
    return this.kv.get(key) ?? null;
  }

  async set(key: string, value: string): Promise<string> {
    this.kv.set(key, value);
    return "OK";
  }

  async del(key: string): Promise<number> {
    const deletedKV = this.kv.delete(key) ? 1 : 0;
    const deletedZ = this.zsets.delete(key) ? 1 : 0;
    return deletedKV || deletedZ;
  }

  async keys(pattern: string): Promise<string[]> {
    const prefix = pattern.replace("*", "");
    const results: string[] = [];
    for (const k of this.kv.keys()) {
      if (k.startsWith(prefix)) results.push(k);
    }
    for (const k of this.zsets.keys()) {
      if (k.startsWith(prefix)) results.push(k);
    }
    return results;
  }

  async zadd(key: string, score: number, member: string): Promise<number> {
    let set = this.zsets.get(key);
    if (!set) {
      set = [];
      this.zsets.set(key, set);
    }
    set.push({ score, member });
    set.sort((a, b) => a.score - b.score);
    return 1;
  }

  async zrangebyscore(key: string, min: number | string, max: number | string): Promise<string[]> {
    const set = this.zsets.get(key) ?? [];
    const minVal = typeof min === "number" ? min : parseFloat(min);
    const maxVal = typeof max === "number" ? max : parseFloat(max);

    return set
      .filter((item) => item.score >= minVal && item.score <= maxVal)
      .map((item) => item.member);
  }

  async zremrangebyscore(key: string, min: number | string, max: number | string): Promise<number> {
    const set = this.zsets.get(key);
    if (!set) return 0;
    const minVal = typeof min === "number" ? min : parseFloat(min);
    const maxVal = typeof max === "number" ? max : parseFloat(max);

    const initialLen = set.length;
    const filtered = set.filter((item) => item.score < minVal || item.score > maxVal);
    this.zsets.set(key, filtered);
    return initialLen - filtered.length;
  }

  clear(): void {
    this.kv.clear();
    this.zsets.clear();
  }
}

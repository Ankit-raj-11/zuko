import { JsonRpcProvider } from "ethers";

export interface IRpcProvider {
  send(method: string, params: unknown[]): Promise<unknown>;
}

export class QuorumProvider {
  private providers: IRpcProvider[];

  constructor(rpcUrlsOrProviders: (IRpcProvider | string)[]) {
    if (rpcUrlsOrProviders.length < 3) {
      throw new Error(
        "[FATAL] QuorumProvider requires exactly 3 RPC URLs/providers. Got: " +
          rpcUrlsOrProviders.length
      );
    }
    this.providers = rpcUrlsOrProviders.map((p) =>
      typeof p === "string" ? new JsonRpcProvider(p) : p
    );
    console.log(
      "[Zuko] QuorumProvider initialized with",
      this.providers.length,
      "providers"
    );
  }

  async call(method: string, params: unknown[]): Promise<unknown> {
    const results = await Promise.allSettled(
      this.providers.map((p) => p.send(method, params))
    );

    const fulfilled = results
      .filter((r): r is PromiseFulfilledResult<unknown> => r.status === "fulfilled")
      .map((r) => r.value);

    // Fewer than 2 responded — hard fail, do not guess
    if (fulfilled.length < 2) {
      const errors = results
        .filter((r): r is PromiseRejectedResult => r.status === "rejected")
        .map((r) => r.reason?.message);
      throw new Error(
        `[FATAL] Quorum failure: only ${fulfilled.length}/3 providers responded. ` +
          `Errors: ${errors.join(" | ")}`
      );
    }

    const serialize = (v: unknown) => JSON.stringify(v);

    // Check first two agree
    if (serialize(fulfilled[0]) === serialize(fulfilled[1])) {
      return fulfilled[0];
    }

    // First two disagree — check if third agrees with either
    if (fulfilled[2] !== undefined) {
      if (serialize(fulfilled[2]) === serialize(fulfilled[0])) return fulfilled[0];
      if (serialize(fulfilled[2]) === serialize(fulfilled[1])) return fulfilled[1];
    }

    // All three disagree, or only 2 responded and they disagree
    throw new Error(
      `[FATAL] Quorum disagreement: RPCs returned different values for ${method}. ` +
        `Results: ${fulfilled.map(serialize).join(" | ")}`
    );
  }
}

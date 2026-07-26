import { JsonRpcProvider } from "ethers";

export interface IRpcProvider {
  send(method: string, params: unknown[]): Promise<unknown>;
}

/**
 * QuorumProvider — 3-endpoint RPC provider requiring 2-of-3 agreement.
 * Protects Zuko from single RPC failure, lag, or malicious RPC response spoofing.
 */
export class QuorumProvider {
  private providers: IRpcProvider[];

  constructor(providers: (IRpcProvider | string)[]) {
    this.providers = providers.map((p) =>
      typeof p === "string" ? new JsonRpcProvider(p) : p
    );
    if (this.providers.length < 3) {
      throw new Error("QuorumProvider requires exactly 3 RPC providers");
    }
  }

  async call(method: string, params: unknown[]): Promise<unknown> {
    const results = await Promise.allSettled(
      this.providers.map((p) => p.send(method, params))
    );

    const fulfilled: unknown[] = [];
    for (const r of results) {
      if (r.status === "fulfilled") {
        fulfilled.push(r.value);
      }
    }

    if (fulfilled.length < 2) {
      throw new Error("Quorum failure: <2 RPCs responded successfully");
    }

    const str0 = JSON.stringify(fulfilled[0]);
    const str1 = JSON.stringify(fulfilled[1]);

    if (str0 === str1) {
      return fulfilled[0];
    }

    // Tie-break with third provider if available
    if (fulfilled.length >= 3) {
      const str2 = JSON.stringify(fulfilled[2]);
      if (str0 === str2) return fulfilled[0];
      if (str1 === str2) return fulfilled[1];
    }

    throw new Error("Quorum disagreement: RPCs returned different values");
  }
}

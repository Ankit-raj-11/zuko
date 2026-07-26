export interface AgentSnapshot {
  agentVault: string;
  vaultCRBIPS: number;
  poolCRBIPS: number;
  blockNumber: number;
  timestamp: number;
}

export class AgentPoller {
  private history = new Map<string, AgentSnapshot[]>();

  recordSnapshot(snapshot: AgentSnapshot): void {
    let list = this.history.get(snapshot.agentVault);
    if (!list) {
      list = [];
      this.history.set(snapshot.agentVault, list);
    }
    list.push(snapshot);
    if (list.length > 100) list.shift();
  }

  computeCRVelocity(agentVault: string): number {
    const list = this.history.get(agentVault);
    if (!list || list.length < 2) return 0;

    const oldest = list[0];
    const latest = list[list.length - 1];
    const blockDiff = latest.blockNumber - oldest.blockNumber;
    if (blockDiff === 0) return 0;

    const crDiffPct = ((latest.vaultCRBIPS - oldest.vaultCRBIPS) / oldest.vaultCRBIPS) * 100;
    return crDiffPct / blockDiff; // velocity in %/block
  }
}

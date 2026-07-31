import { Broadcaster } from "../ws/broadcaster";

export interface DemoState {
  activeScenario: string | null;
  isPaused: boolean;
  severity: "MEDIUM" | "HIGH" | "CRITICAL" | null;
  opsPausedUntil: number;
  transfersPausedUntil: number;
  lastIncidentId: number;
  logs: string[];
}

export class DemoOrchestrator {
  private broadcaster: Broadcaster;
  private state: DemoState = {
    activeScenario: null,
    isPaused: false,
    severity: null,
    opsPausedUntil: 0,
    transfersPausedUntil: 0,
    lastIncidentId: 0,
    logs: ["[ORCHESTRATOR] Zuko Attack Demo Orchestrator initialized."],
  };

  constructor(broadcaster: Broadcaster) {
    this.broadcaster = broadcaster;
  }

  public getStatus(): DemoState {
    return { ...this.state };
  }

  public async triggerScenario(scenarioId: string): Promise<DemoState> {
    const incidentId = ++this.state.lastIncidentId;
    const now = Math.floor(Date.now() / 1000);

    let severity: "MEDIUM" | "HIGH" | "CRITICAL" = "MEDIUM";
    let opsDuration = 3600; // 1 hour
    let transferDuration = 0;

    switch (scenarioId) {
      case "RULE-1":
        severity = "MEDIUM";
        opsDuration = 3600;
        transferDuration = 0;
        break;
      case "RULE-2":
        severity = "MEDIUM";
        opsDuration = 3600;
        transferDuration = 0;
        break;
      case "RULE-3":
        severity = "HIGH";
        opsDuration = 14400; // 4 hours
        transferDuration = 14400;
        break;
      case "RULE-4":
        severity = "CRITICAL";
        opsDuration = 21600; // 6 hours
        transferDuration = 21600;
        break;
    }

    this.state.activeScenario = scenarioId;
    this.state.isPaused = true;
    this.state.severity = severity;
    this.state.opsPausedUntil = now + opsDuration;
    this.state.transfersPausedUntil = transferDuration > 0 ? now + transferDuration : 0;

    const logEntry = `[${new Date().toISOString()}] Incident #${incidentId}: ${scenarioId} triggered (${severity}). Ops Paused: ${opsDuration}s, Transfers: ${transferDuration}s.`;
    this.state.logs.push(logEntry);

    // Broadcast live WebSocket notification to connected clients
    this.broadcaster.broadcast({
      type: "ZUKO_DEMO_ALERT",
      incidentId,
      scenarioId,
      severity,
      isPaused: true,
      opsPausedUntil: this.state.opsPausedUntil,
      transfersPausedUntil: this.state.transfersPausedUntil,
      timestamp: Date.now(),
    });

    return this.getStatus();
  }

  public async resumeGuardian(): Promise<DemoState> {
    this.state.isPaused = false;
    this.state.activeScenario = null;
    this.state.severity = null;
    this.state.opsPausedUntil = 0;
    this.state.transfersPausedUntil = 0;

    const logEntry = `[${new Date().toISOString()}] Guardian Fast Resume executed. Protocol emergency pause lifted. System status: NORMAL.`;
    this.state.logs.push(logEntry);

    this.broadcaster.broadcast({
      type: "ZUKO_DEMO_RESUME",
      isPaused: false,
      timestamp: Date.now(),
    });

    return this.getStatus();
  }
}

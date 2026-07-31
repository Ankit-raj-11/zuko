export type ZukoWSMessage =
  | {
      type: "FTSO_UPDATE";
      blockNumber: number;
      timestamp: number;
      prices: { feedId: string; symbol: string; value: number; decimals: number }[];
    }
  | {
      type: "ASSET_MANAGER_EVENT";
      blockNumber: number;
      eventName: string;
      txHash: string;
      args: Record<string, unknown>;
    }
  | {
      type: "ZUKO_ALERT";
      severity: number;
      rules: number;
      message: string;
      timestamp: number;
    }
  | {
      type: "ZUKO_DEMO_ALERT";
      incidentId: number;
      scenarioId: string;
      severity: string;
      isPaused: boolean;
      opsPausedUntil: number;
      transfersPausedUntil: number;
      timestamp: number;
    }
  | {
      type: "ZUKO_DEMO_RESUME";
      isPaused: boolean;
      timestamp: number;
    };

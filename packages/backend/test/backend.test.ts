import assert from "assert";
import test, { describe } from "node:test";
import { QuorumProvider, IRpcProvider } from "../src/rpc/quorum";
import { InMemoryRedisStore } from "../src/cache/redis";
import { FTSORingBuffer } from "../src/feeds/ringBuffer";
import { EventIndexer } from "../src/events/eventIndexer";
import { AgentPoller } from "../src/agents/agentPoller";
import { Broadcaster } from "../src/ws/broadcaster";

describe("Phase 1 Backend Unit Tests", () => {
  test("PHASE-1-TC-01: QuorumProvider — 2-of-3 agreement passes", async () => {
    const mock1: IRpcProvider = { send: async () => 100 };
    const mock2: IRpcProvider = { send: async () => 100 };
    const mock3: IRpcProvider = { send: async () => 100 };

    const quorum = new QuorumProvider([mock1, mock2, mock3]);
    const res = await quorum.call("eth_blockNumber", []);
    assert.strictEqual(res, 100);
  });

  test("PHASE-1-TC-02: QuorumProvider — 1-of-3 failure is tolerated", async () => {
    const mock1: IRpcProvider = { send: async () => 100 };
    const mock2: IRpcProvider = { send: async () => 100 };
    const mock3: IRpcProvider = { send: async () => { throw new Error("RPC error"); } };

    const quorum = new QuorumProvider([mock1, mock2, mock3]);
    const res = await quorum.call("eth_blockNumber", []);
    assert.strictEqual(res, 100);
  });

  test("PHASE-1-TC-03: QuorumProvider — disagreement throws", async () => {
    const mock1: IRpcProvider = { send: async () => 100 };
    const mock2: IRpcProvider = { send: async () => 200 };
    const mock3: IRpcProvider = { send: async () => { throw new Error("RPC error"); } };

    const quorum = new QuorumProvider([mock1, mock2, mock3]);
    await assert.rejects(async () => {
      await quorum.call("eth_blockNumber", []);
    }, /Quorum disagreement/);
  });

  test("PHASE-1-TC-04: FTSO ring buffer — fills correctly & caps at 50", async () => {
    const store = new InMemoryRedisStore();
    const buffer = new FTSORingBuffer(store);

    for (let i = 1; i <= 60; i++) {
      await buffer.addSample("XRP_USD", i, 100 + i);
    }

    const samples = await buffer.getSamples("XRP_USD");
    assert.strictEqual(samples.length, 50);
    assert.strictEqual(samples[0].blockNumber, 11);
    assert.strictEqual(samples[49].blockNumber, 60);
  });

  test("PHASE-1-TC-05: FTSO ring buffer — z-score with stable data returns 0", async () => {
    const store = new InMemoryRedisStore();
    const buffer = new FTSORingBuffer(store);

    for (let i = 1; i <= 50; i++) {
      await buffer.addSample("XRP_USD", i, 1.0);
    }

    const z = await buffer.computeZScore("XRP_USD");
    assert.strictEqual(z, 0);
  });

  test("PHASE-1-TC-06: FTSO ring buffer — z-score with spike", async () => {
    const store = new InMemoryRedisStore();
    const buffer = new FTSORingBuffer(store);

    for (let i = 1; i <= 49; i++) {
      await buffer.addSample("XRP_USD", i, 1.0);
    }
    await buffer.addSample("XRP_USD", 50, 1.5); // +50% spike

    const z = await buffer.computeZScore("XRP_USD");
    assert.ok(z > 200, `Expected z-score > 200 (2.0σ), got ${z}`);
  });

  test("PHASE-1-TC-16: Agent CR velocity — computed correctly", () => {
    const poller = new AgentPoller();
    const vault = "0xAgent1";

    poller.recordSnapshot({ agentVault: vault, vaultCRBIPS: 17000, poolCRBIPS: 17000, blockNumber: 100, timestamp: 1000 });
    poller.recordSnapshot({ agentVault: vault, vaultCRBIPS: 16800, poolCRBIPS: 16800, blockNumber: 101, timestamp: 1002 });
    poller.recordSnapshot({ agentVault: vault, vaultCRBIPS: 16500, poolCRBIPS: 16500, blockNumber: 102, timestamp: 1004 });
    poller.recordSnapshot({ agentVault: vault, vaultCRBIPS: 16100, poolCRBIPS: 16100, blockNumber: 103, timestamp: 1006 });
    poller.recordSnapshot({ agentVault: vault, vaultCRBIPS: 15600, poolCRBIPS: 15600, blockNumber: 104, timestamp: 1008 });

    const velocity = poller.computeCRVelocity(vault);
    assert.ok(velocity < 0, "Velocity should be negative for declining CR");
  });

  test("PHASE-1-TC-18: WebSocket broadcast — FTSO_UPDATE received by client", () => {
    const broadcaster = new Broadcaster();
    let received = false;

    broadcaster.subscribe((msg) => {
      const parsed = JSON.parse(msg);
      if (parsed.type === "FTSO_UPDATE") received = true;
    });

    broadcaster.broadcast({
      type: "FTSO_UPDATE",
      blockNumber: 100,
      timestamp: Date.now(),
      prices: [{ feedId: "XRP_USD", symbol: "XRP", value: 0.58, decimals: 5 }],
    });

    assert.strictEqual(received, true);
  });

  test("PHASE-1-TC-19: [EDGE CASE 2] Reorg detection — orphaned event is dropped", async () => {
    const store = new InMemoryRedisStore();
    const mockQuorum = new QuorumProvider([
      { send: async () => ({ hash: "0xCanonicalHashNew" }) },
      { send: async () => ({ hash: "0xCanonicalHashNew" }) },
      { send: async () => ({ hash: "0xCanonicalHashNew" }) },
    ]);

    const indexer = new EventIndexer(store, mockQuorum);
    let reorgAlerted = false;

    await indexer.stagePendingEvent({
      txHash: "0xTx1",
      logIndex: 0,
      blockNumber: 100,
      blockHash: "0xOldOrphanedHash",
      eventName: "RedemptionRequested",
      fxrpAmount: "1000",
      timestamp: Date.now(),
    });

    const processed = await indexer.processPendingEvents(102, (msg) => {
      if (msg.includes("Reorg detected")) reorgAlerted = true;
    });

    assert.strictEqual(processed, 0);
    assert.strictEqual(reorgAlerted, true);
    assert.strictEqual(await indexer.get24hVolume(102), 0);
  });

  test("PHASE-1-TC-20: [EDGE CASE 2] Confirmed event — writes to window after 2 blocks", async () => {
    const store = new InMemoryRedisStore();
    const mockQuorum = new QuorumProvider([
      { send: async () => ({ hash: "0xValidHash" }) },
      { send: async () => ({ hash: "0xValidHash" }) },
      { send: async () => ({ hash: "0xValidHash" }) },
    ]);

    const indexer = new EventIndexer(store, mockQuorum);

    await indexer.stagePendingEvent({
      txHash: "0xTx1",
      logIndex: 0,
      blockNumber: 100,
      blockHash: "0xValidHash",
      eventName: "RedemptionRequested",
      fxrpAmount: "1000",
      timestamp: Date.now(),
    });

    const processed = await indexer.processPendingEvents(102);

    assert.strictEqual(processed, 1);
    assert.strictEqual(await indexer.get24hVolume(102), 1000);
  });

  test("PHASE-1-TC-21: [EDGE CASE 2] Event at block N+1 — not yet committed (lag not met)", async () => {
    const store = new InMemoryRedisStore();
    const mockQuorum = new QuorumProvider([
      { send: async () => ({ hash: "0xValidHash" }) },
      { send: async () => ({ hash: "0xValidHash" }) },
      { send: async () => ({ hash: "0xValidHash" }) },
    ]);

    const indexer = new EventIndexer(store, mockQuorum);

    await indexer.stagePendingEvent({
      txHash: "0xTx1",
      logIndex: 0,
      blockNumber: 100,
      blockHash: "0xValidHash",
      eventName: "RedemptionRequested",
      fxrpAmount: "1000",
      timestamp: Date.now(),
    });

    const processed = await indexer.processPendingEvents(101); // Lag of 1 only

    assert.strictEqual(processed, 0);
    assert.strictEqual(await indexer.get24hVolume(101), 0);
  });

  test("PHASE-1-TC-22 & 23: [EDGE CASE 3] Cold-start backfill — gates Rule 3 & populates baseline", async () => {
    const store = new InMemoryRedisStore();
    const mockQuorum = new QuorumProvider([
      { send: async () => ({ hash: "0xHash" }) },
      { send: async () => ({ hash: "0xHash" }) },
      { send: async () => ({ hash: "0xHash" }) },
    ]);

    const indexer = new EventIndexer(store, mockQuorum);
    assert.strictEqual(indexer.rule3Enabled, false);

    await indexer.backfillRedemptionBaseline(50000, async (start) => {
      if (start === 50000 - EventIndexer.BLOCKS_PER_24H) {
        return [
          {
            txHash: "0xBackfillTx",
            logIndex: 0,
            blockNumber: 40000,
            blockHash: "0xHash",
            eventName: "RedemptionRequested",
            fxrpAmount: "500000",
            timestamp: Date.now(),
          },
        ];
      }
      return [];
    });

    assert.strictEqual(indexer.rule3Enabled, true);
    const vol = await indexer.get24hVolume(50000);
    assert.strictEqual(vol, 500000);
  });
});

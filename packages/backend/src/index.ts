import Fastify from "fastify";
import cors from "@fastify/cors";
import websocket from "@fastify/websocket";
import { ethers } from "ethers";
import { QuorumProvider } from "./rpc/quorum";
import { resolveContracts, ResolvedContracts } from "./rpc/registry";
import { InMemoryRedisStore } from "./cache/redis";
import { FTSORingBuffer } from "./feeds/ringBuffer";
import { EventIndexer } from "./events/eventIndexer";
import { AgentPoller } from "./agents/agentPoller";
import { Broadcaster } from "./ws/broadcaster";
import { DemoOrchestrator } from "./demo/orchestrator";

const server = Fastify({ logger: true });
const store = new InMemoryRedisStore();
const broadcaster = new Broadcaster();

const RPC_1 = process.env.COSTON2_RPC_1 || "https://coston2-api.flare.network/ext/C/rpc";
const RPC_2 = process.env.COSTON2_RPC_2 || "https://coston2.enosys.global/ext/C/rpc";
const RPC_3 = process.env.COSTON2_RPC_3 || "https://rpc.ankr.com/flare_coston2";

const quorum = new QuorumProvider([RPC_1, RPC_2, RPC_3]);
const ringBuffer = new FTSORingBuffer(store);
const indexer = new EventIndexer(store, quorum);
const agentPoller = new AgentPoller();

let contracts: ResolvedContracts | null = null;

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_1);
  contracts = await resolveContracts(provider);

  await server.register(cors, { origin: "*" });
  await server.register(websocket);

  // WebSocket endpoint for live monitoring stream
  server.get("/ws", { websocket: true }, (connection) => {
    const unsubscribe = broadcaster.subscribe((msg) => {
      connection.socket.send(msg);
    });
    connection.socket.on("close", () => unsubscribe());
  });

  // REST: GET /api/feeds — FTSO history for chart mount
  server.get("/api/feeds", async (req, reply) => {
    const feedId = (req.query as { feedId?: string }).feedId || "XRP_USD";
    const samples = await ringBuffer.getSamples(feedId);
    const zScore = await ringBuffer.computeZScore(feedId);
    return reply.send({ feedId, samples, zScore });
  });

  // REST: GET /api/agents — agent vault snapshot
  server.get("/api/agents", async (_req, reply) => {
    return reply.send({
      agents: [
        { agentVault: "0xMockAgentVault1", vaultCRBIPS: 17000, poolCRBIPS: 17000, status: "HEALTHY" },
        { agentVault: "0xMockAgentVault2", vaultCRBIPS: 16500, poolCRBIPS: 16500, status: "HEALTHY" },
      ],
      timestamp: Date.now(),
    });
  });

  // REST: GET /api/incidents — paginated forensic log
  server.get("/api/incidents", async (_req, reply) => {
    return reply.send({
      incidents: [],
      total: 0,
      timestamp: Date.now(),
    });
  });

  // REST: Demo Orchestrator Endpoints for Attack Presentation
  const orchestrator = new DemoOrchestrator(broadcaster);

  server.get("/api/demo/status", async (_req, reply) => {
    return reply.send(orchestrator.getStatus());
  });

  server.post("/api/demo/trigger", async (req, reply) => {
    const { scenarioId } = (req.body as { scenarioId?: string }) || {};
    if (!scenarioId) {
      return reply.status(400).send({ error: "Missing scenarioId parameter" });
    }
    const state = await orchestrator.triggerScenario(scenarioId);
    return reply.send(state);
  });

  server.post("/api/demo/resume", async (_req, reply) => {
    const state = await orchestrator.resumeGuardian();
    return reply.send(state);
  });

  // Health check endpoint
  server.get("/health", async () => {
    return {
      status: "ok",
      timestamp: Date.now(),
      rule3Enabled: indexer.isRule3Enabled(),
      contracts,
    };
  });

  const port = parseInt(process.env.PORT || "3001", 10);
  const host = "0.0.0.0";
  await server.listen({ port, host });
  console.log(`[Zuko Backend] Read-Only Monitoring Core running on http://${host}:${port}`);
}

if (require.main === module) {
  main().catch((err) => {
    console.error("[Zuko Backend] Boot error:", err);
    process.exit(1);
  });
}

export { server, main, quorum, ringBuffer, indexer, agentPoller, broadcaster, contracts };

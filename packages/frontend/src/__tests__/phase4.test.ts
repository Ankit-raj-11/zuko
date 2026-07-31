import { describe, it, expect } from "vitest";
import { createPublicClient, http, parseAbi } from "viem";
import { coston2, COSTON2_CONTRACT_REGISTRY } from "@/lib/chains";

const REGISTRY_ABI = parseAbi([
  "function getContractAddressByName(string name) view returns (address)",
]);

const FTSO_V2_ABI = parseAbi([
  "function getFeedById(bytes21 feedId) view returns (uint256 value, int8 decimals, uint64 timestamp)",
]);

function buildFeedId(category: number, name: string): `0x${string}` {
  const catHex = category.toString(16).padStart(2, "0");
  const nameHex = Buffer.from(name, "ascii").toString("hex");
  const paddedName = nameHex.padEnd(40, "0");
  return `0x${catHex}${paddedName}` as `0x${string}`;
}

const XRP_USD_FEED = buildFeedId(1, "XRP/USD");

describe("Phase 4 Frontend Data Layer Tests (Coston2 Live Integration)", () => {
  const client = createPublicClient({
    chain: coston2,
    transport: http("https://rpc.ankr.com/flare_coston2"),
  });

  // PHASE-4-TC-01: ContractRegistry resolves FtsoV2 address
  it("PHASE-4-TC-01: ContractRegistry resolves FtsoV2 address", async () => {
    const ftsoAddress = await client.readContract({
      address: COSTON2_CONTRACT_REGISTRY as `0x${string}`,
      abi: REGISTRY_ABI,
      functionName: "getContractAddressByName",
      args: ["FtsoV2"],
    });

    expect(ftsoAddress).toBeDefined();
    expect(ftsoAddress).toMatch(/^0x[a-fA-F0-9]{40}$/);
  });

  // PHASE-4-TC-02: Reads real on-chain XRP/USD price from FtsoV2
  it("PHASE-4-TC-02: FtsoV2 returns real positive XRP/USD price on Coston2", async () => {
    const ftsoAddress = (await client.readContract({
      address: COSTON2_CONTRACT_REGISTRY as `0x${string}`,
      abi: REGISTRY_ABI,
      functionName: "getContractAddressByName",
      args: ["FtsoV2"],
    })) as `0x${string}`;

    const [value, decimals, timestamp] = (await client.readContract({
      address: ftsoAddress,
      abi: FTSO_V2_ABI,
      functionName: "getFeedById",
      args: [XRP_USD_FEED],
    })) as [bigint, number, bigint];

    const price = Number(value) / Math.pow(10, Math.abs(decimals));
    console.log("Live Coston2 XRP/USD Price:", price, "at ts:", timestamp.toString());
    expect(price).toBeGreaterThan(0);
  });

  // PHASE-4-TC-04: AssetManagerController resolution from ContractRegistry
  it("PHASE-4-TC-04: ContractRegistry resolves AssetManagerController address", async () => {
    const controllerAddr = await client.readContract({
      address: COSTON2_CONTRACT_REGISTRY as `0x${string}`,
      abi: REGISTRY_ABI,
      functionName: "getContractAddressByName",
      args: ["AssetManagerController"],
    });

    expect(controllerAddr).toBeDefined();
    expect(controllerAddr).toMatch(/^0x[a-fA-F0-9]{40}$/);
  });

  // PHASE-4-TC-08: Coston2 RPC node responds to chain ID queries
  it("PHASE-4-TC-08: Coston2 RPC provider responds with correct Chain ID (114)", async () => {
    const chainId = await client.getChainId();
    expect(chainId).toBe(114);
  });

  // PHASE-4-TC-10: Blockscout URL structure helper test
  it("PHASE-4-TC-10: Blockscout tx link format produces valid URL", () => {
    const sampleTxHash = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    const explorerUrl = `${coston2.blockExplorers.default.url}/tx/${sampleTxHash}`;

    expect(explorerUrl).toBe(
      `https://coston2-explorer.flare.network/tx/${sampleTxHash}`
    );
  });
});

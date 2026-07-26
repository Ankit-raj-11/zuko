/**
 * @module ContractRegistry
 * @description Resolves all Flare protocol contract addresses at runtime.
 *              The ContractRegistry address is the ONLY constant in the entire project.
 *              Used by both the Next.js frontend and the Fastify backend.
 *
 * @dev Registry address: 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019
 *      This address is the same across Coston2, Songbird, and Flare mainnet.
 */

import { Contract, JsonRpcProvider } from "ethers";

// ── The only hardcoded constant in the entire project ────────────────────────
export const REGISTRY_ADDRESS = "0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019";

// ── ABIs ─────────────────────────────────────────────────────────────────────

const REGISTRY_ABI = [
  "function getContractAddressByName(string calldata name) external view returns (address)",
];

const ASSET_MANAGER_CONTROLLER_ABI = [
  "function getAssetManagers() external view returns (address[] memory)",
];

const ASSET_MANAGER_INFO_ABI = [
  "function fAsset() external view returns (address)",
];

const FASSET_ABI = [
  "function symbol() external view returns (string memory)",
];

// ── Types ────────────────────────────────────────────────────────────────────

export interface ResolvedContracts {
  /** FTSOv2 price feed contract address */
  ftsoV2: string;
  /** FDC verification contract address */
  fdcVerification: string;
  /** AssetManager address for FXRP */
  assetManager: string;
}

// ── Internal helpers ─────────────────────────────────────────────────────────

/**
 * Resolve the AssetManager for a specific FAsset symbol (e.g. "FXRP").
 * Steps:
 *   1. Registry → AssetManagerController address
 *   2. AssetManagerController → all AssetManager addresses
 *   3. For each, read its fAsset → symbol and match
 */
async function resolveAssetManager(
  registry: Contract,
  provider: JsonRpcProvider,
  targetSymbol: string
): Promise<string> {
  const controllerAddr = await registry.getContractAddressByName(
    "AssetManagerController"
  );
  const controller = new Contract(
    controllerAddr,
    ASSET_MANAGER_CONTROLLER_ABI,
    provider
  );

  const managers: string[] = await controller.getAssetManagers();

  for (const managerAddr of managers) {
    try {
      const manager = new Contract(
        managerAddr,
        ASSET_MANAGER_INFO_ABI,
        provider
      );
      const fAssetAddr = await manager.fAsset();
      const fAsset = new Contract(fAssetAddr, FASSET_ABI, provider);
      const symbol = await fAsset.symbol();

      if (symbol === targetSymbol) {
        return managerAddr;
      }
    } catch {
      // Skip managers that don't match the expected ABI
      continue;
    }
  }

  throw new Error(
    `AssetManager for ${targetSymbol} not found. ` +
      `Checked ${managers.length} managers via AssetManagerController at ${controllerAddr}`
  );
}

// ── Public API ───────────────────────────────────────────────────────────────

/**
 * Resolve all required contract addresses from the Flare ContractRegistry.
 * Never hardcode addresses — this is the single source of truth.
 *
 * @param provider JsonRpcProvider connected to Coston2 or Flare mainnet
 * @returns ResolvedContracts with all addresses needed by Zuko
 */
export async function resolveContracts(
  provider: JsonRpcProvider
): Promise<ResolvedContracts> {
  const registry = new Contract(REGISTRY_ADDRESS, REGISTRY_ABI, provider);

  const [ftsoV2, fdcVerification, assetManager] = await Promise.all([
    registry.getContractAddressByName("FtsoV2") as Promise<string>,
    registry.getContractAddressByName("FdcVerification") as Promise<string>,
    resolveAssetManager(registry, provider, "FXRP"),
  ]);

  // Validate none are zero addresses
  const zeroAddr = "0x0000000000000000000000000000000000000000";
  if (ftsoV2 === zeroAddr) throw new Error("FtsoV2 resolved to zero address");
  if (fdcVerification === zeroAddr)
    throw new Error("FdcVerification resolved to zero address");
  if (assetManager === zeroAddr)
    throw new Error("AssetManager(FXRP) resolved to zero address");

  return { ftsoV2, fdcVerification, assetManager };
}


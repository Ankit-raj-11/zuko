import { Contract, JsonRpcProvider, ZeroAddress } from "ethers";

export const REGISTRY_ADDRESS = "0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019";

const REGISTRY_ABI = [
  "function getContractAddressByName(string name) view returns (address)",
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

export interface ResolvedContracts {
  ftsoV2: string;
  fdcVerif: string;
  assetManager: string;
}

export async function resolveAssetManager(
  registry: Contract,
  provider: JsonRpcProvider,
  targetSymbol: string
): Promise<string> {
  const controllerAddr = await registry.getContractAddressByName("AssetManagerController");
  const controller = new Contract(controllerAddr, ASSET_MANAGER_CONTROLLER_ABI, provider);
  const managers: string[] = await controller.getAssetManagers();

  for (const managerAddr of managers) {
    try {
      const manager = new Contract(managerAddr, ASSET_MANAGER_INFO_ABI, provider);
      const fAssetAddr = await manager.fAsset();
      const fAsset = new Contract(fAssetAddr, FASSET_ABI, provider);
      const symbol = await fAsset.symbol();
      if (symbol === targetSymbol) {
        return managerAddr;
      }
    } catch {
      continue;
    }
  }

  throw new Error(`AssetManager for ${targetSymbol} not found`);
}

export async function resolveContracts(
  provider: JsonRpcProvider
): Promise<ResolvedContracts> {
  const registry = new Contract(REGISTRY_ADDRESS, REGISTRY_ABI, provider);

  const [ftsoV2, fdcVerif, assetManager] = await Promise.all([
    registry.getContractAddressByName("FtsoV2"),
    registry.getContractAddressByName("FdcVerification"),
    resolveAssetManager(registry, provider, "FXRP").catch(() => registry.getContractAddressByName("AssetManager")),
  ]).catch((err) => {
    console.error("[FATAL] ContractRegistry resolution failed:", err);
    throw err;
  });

  const zero = ZeroAddress;
  if (ftsoV2 === zero || fdcVerif === zero || assetManager === zero) {
    console.error("[FATAL] One or more contracts resolved to zero address.", {
      ftsoV2,
      fdcVerif,
      assetManager,
    });
    throw new Error("One or more contracts resolved to zero address");
  }

  console.log("[Zuko] Contracts resolved:", { ftsoV2, fdcVerif, assetManager });
  return { ftsoV2, fdcVerif, assetManager };
}

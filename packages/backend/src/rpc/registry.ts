import { Contract, JsonRpcProvider } from "ethers";

export const REGISTRY_ADDRESS = "0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019";

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

export interface ResolvedContracts {
  ftsoV2: string;
  fdcVerification: string;
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

export async function resolveContracts(provider: JsonRpcProvider): Promise<ResolvedContracts> {
  const registry = new Contract(REGISTRY_ADDRESS, REGISTRY_ABI, provider);
  const [ftsoV2, fdcVerification, assetManager] = await Promise.all([
    registry.getContractAddressByName("FtsoV2") as Promise<string>,
    registry.getContractAddressByName("FdcVerification") as Promise<string>,
    resolveAssetManager(registry, provider, "FXRP"),
  ]);

  const zeroAddr = "0x0000000000000000000000000000000000000000";
  if (ftsoV2 === zeroAddr) throw new Error("FtsoV2 resolved to zero address");
  if (fdcVerification === zeroAddr) throw new Error("FdcVerification resolved to zero address");
  if (assetManager === zeroAddr) throw new Error("AssetManager(FXRP) resolved to zero address");

  return { ftsoV2, fdcVerification, assetManager };
}

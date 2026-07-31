"use client";

import React, { useState } from "react";
import { useAgentVaults, type AgentVault } from "@/hooks/useAgentVaults";
import { ExternalLink, Search, ShieldAlert, X, ChevronRight } from "lucide-react";

export default function AgentsPage() {
  const { vaults, loading, error } = useAgentVaults();
  const [searchTerm, setSearchTerm] = useState("");
  const [selectedVault, setSelectedVault] = useState<AgentVault | null>(null);

  const filteredVaults = vaults.filter(
    (v) =>
      v.vaultAddress.toLowerCase().includes(searchTerm.toLowerCase()) ||
      v.ownerAddress.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-xl font-bold text-slate-100 flex items-center gap-2">
              <span>Agent Vault Collateral Monitor</span>
              <span className="text-xs px-2 py-0.5 rounded-full bg-slate-900 border border-slate-800 text-slate-400 font-mono">
                Rule 2 Active
              </span>
            </h1>
            <p className="text-xs text-slate-400 mt-1">
              Real-time collateral ratio (CR) tracking and cliff velocity monitoring for all registered Coston2 agent vaults.
            </p>
          </div>

          {/* Search Input */}
          <div className="relative w-64">
            <Search className="w-4 h-4 absolute left-3 top-2.5 text-slate-500" />
            <input
              type="text"
              placeholder="Search vault or owner address..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full pl-9 pr-3 py-1.5 bg-slate-900 border border-slate-800 rounded-lg text-xs text-slate-200 placeholder-slate-500 focus:outline-none focus:border-slate-700"
            />
          </div>
        </div>
      </div>

      {/* Agents Table */}
      <div className="bg-slate-900/40 rounded-xl border border-slate-800/80 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs text-slate-300">
            <thead className="bg-slate-900/80 text-slate-400 font-medium uppercase border-b border-slate-800">
              <tr>
                <th className="p-3.5">Agent Vault</th>
                <th className="p-3.5">Owner Address</th>
                <th className="p-3.5">Collateral Ratio (CR)</th>
                <th className="p-3.5">Velocity (Rule 2)</th>
                <th className="p-3.5 text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/50">
              {loading && (
                <tr>
                  <td colSpan={5} className="p-6 text-center text-slate-500">
                    Querying agent vaults from Coston2 AssetManager...
                  </td>
                </tr>
              )}

              {error && (
                <tr>
                  <td colSpan={5} className="p-6 text-center text-red-400 font-mono">
                    {error}
                  </td>
                </tr>
              )}

              {!loading && filteredVaults.length === 0 && (
                <tr>
                  <td colSpan={5} className="p-6 text-center text-slate-500">
                    No matching agent vaults found.
                  </td>
                </tr>
              )}

              {filteredVaults.map((vault) => {
                const crPct = vault.vaultCRPct;
                const isCliff = crPct < 150;
                const isWarning = crPct >= 150 && crPct < 175;

                return (
                  <tr
                    key={vault.vaultAddress}
                    onClick={() => setSelectedVault(vault)}
                    className="hover:bg-slate-900/60 cursor-pointer transition-colors"
                  >
                    <td className="p-3.5 font-mono text-slate-200 font-medium">
                      {vault.vaultAddress}
                    </td>
                    <td className="p-3.5 font-mono text-slate-400">
                      {vault.ownerAddress.slice(0, 10)}...{vault.ownerAddress.slice(-8)}
                    </td>
                    <td className="p-3.5">
                      <div className="flex items-center gap-3">
                        <span
                          className={`font-mono font-bold w-14 ${
                            isCliff
                              ? "text-red-400"
                              : isWarning
                              ? "text-amber-400"
                              : "text-emerald-400"
                          }`}
                        >
                          {crPct.toFixed(1)}%
                        </span>
                        <div className="flex-1 h-2 bg-slate-950 rounded-full overflow-hidden border border-slate-800 w-28">
                          <div
                            className={`h-full rounded-full transition-all ${
                              isCliff
                                ? "bg-red-500"
                                : isWarning
                                ? "bg-amber-500"
                                : "bg-emerald-500"
                            }`}
                            style={{ width: `${Math.min(100, (crPct / 250) * 100)}%` }}
                          />
                        </div>
                      </div>
                    </td>
                    <td className="p-3.5">
                      <span
                        className={`inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[10px] font-semibold border ${
                          isCliff
                            ? "bg-red-950/80 text-red-400 border-red-800/60"
                            : isWarning
                            ? "bg-amber-950/80 text-amber-400 border-amber-800/60"
                            : "bg-emerald-950/80 text-emerald-400 border-emerald-800/60"
                        }`}
                      >
                        <span
                          className={`w-1.5 h-1.5 rounded-full ${
                            isCliff
                              ? "bg-red-500 animate-ping"
                              : isWarning
                              ? "bg-amber-500"
                              : "bg-emerald-500"
                          }`}
                        />
                        {isCliff ? "CLIFF ALERT" : isWarning ? "DECLINING" : "STABLE"}
                      </span>
                    </td>
                    <td className="p-3.5 text-right">
                      <button className="text-slate-400 hover:text-slate-200 inline-flex items-center gap-1 text-xs">
                        Details <ChevronRight className="w-3.5 h-3.5" />
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {/* Agent Detail Drawer */}
      {selectedVault && (
        <div className="fixed inset-0 z-50 flex justify-end bg-slate-950/70 backdrop-blur-sm">
          <div className="w-full max-w-md bg-slate-900 border-l border-slate-800 p-6 flex flex-col justify-between overflow-y-auto">
            <div className="space-y-6">
              {/* Drawer Header */}
              <div className="flex items-center justify-between border-b border-slate-800 pb-4">
                <div>
                  <h2 className="text-base font-bold text-slate-100">
                    Agent Vault Detail
                  </h2>
                  <p className="text-xs text-slate-400 font-mono mt-0.5">
                    {selectedVault.vaultAddress.slice(0, 14)}...
                  </p>
                </div>
                <button
                  onClick={() => setSelectedVault(null)}
                  className="p-1 rounded-lg hover:bg-slate-800 text-slate-400 hover:text-slate-200"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>

              {/* Collateral Ratio Gauge */}
              <div className="p-4 rounded-xl bg-slate-950 border border-slate-800 space-y-2">
                <div className="flex items-center justify-between text-xs">
                  <span className="text-slate-400">Current Collateral Ratio</span>
                  <span
                    className={`font-mono font-bold ${
                      selectedVault.vaultCRPct < 150
                        ? "text-red-400"
                        : selectedVault.vaultCRPct < 175
                        ? "text-amber-400"
                        : "text-emerald-400"
                    }`}
                  >
                    {selectedVault.vaultCRPct.toFixed(1)}%
                  </span>
                </div>
                <div className="h-3 bg-slate-900 rounded-full overflow-hidden border border-slate-800">
                  <div
                    className={`h-full rounded-full ${
                      selectedVault.vaultCRPct < 150
                        ? "bg-red-500"
                        : selectedVault.vaultCRPct < 175
                        ? "bg-amber-500"
                        : "bg-emerald-500"
                    }`}
                    style={{
                      width: `${Math.min(100, (selectedVault.vaultCRPct / 250) * 100)}%`,
                    }}
                  />
                </div>
                <div className="flex justify-between text-[10px] text-slate-500 font-mono pt-1">
                  <span>Min Threshold: 150%</span>
                  <span>Target: 185%+</span>
                </div>
              </div>

              {/* Metadata List */}
              <div className="space-y-3 text-xs">
                <div className="p-3 rounded-lg bg-slate-950/60 border border-slate-800/80">
                  <span className="block text-[10px] text-slate-500 uppercase font-mono mb-1">
                    Owner Management Address
                  </span>
                  <span className="font-mono text-slate-200 break-all">
                    {selectedVault.ownerAddress}
                  </span>
                </div>

                <div className="p-3 rounded-lg bg-slate-950/60 border border-slate-800/80">
                  <span className="block text-[10px] text-slate-500 uppercase font-mono mb-1">
                    Underlying XRPL Address String
                  </span>
                  <span className="font-mono text-slate-200">
                    r3k19028471920384719203847
                  </span>
                </div>

                <div className="p-3 rounded-lg bg-slate-950/60 border border-slate-800/80 flex items-center justify-between">
                  <span className="text-slate-400">Minting Vault CR Setting</span>
                  <span className="font-mono text-slate-200">
                    {(selectedVault.mintingVaultCR / 100).toFixed(0)}%
                  </span>
                </div>

                <div className="p-3 rounded-lg bg-slate-950/60 border border-slate-800/80 flex items-center justify-between">
                  <span className="text-slate-400">Publicly Available</span>
                  <span className="font-mono text-emerald-400">
                    {selectedVault.publiclyAvailable ? "YES" : "NO"}
                  </span>
                </div>
              </div>
            </div>

            {/* Blockscout External Link */}
            <div className="pt-6 border-t border-slate-800">
              <a
                href={`https://coston2-explorer.flare.network/address/${selectedVault.vaultAddress}`}
                target="_blank"
                rel="noreferrer"
                className="w-full py-2.5 px-4 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-100 font-semibold text-xs flex items-center justify-center gap-2 transition-colors"
              >
                <span>View on Coston2 Blockscout</span>
                <ExternalLink className="w-3.5 h-3.5" />
              </a>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

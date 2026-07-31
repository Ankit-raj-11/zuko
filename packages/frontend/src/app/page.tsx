"use client";

import React from "react";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { FTSOChart } from "@/components/FTSOChart";
import { useFTSOFeeds } from "@/hooks/useFTSOFeeds";
import { useZukoStatus } from "@/hooks/useZukoStatus";
import { useAgentVaults } from "@/hooks/useAgentVaults";
import { useAssetManagerEvents } from "@/hooks/useAssetManagerEvents";

export default function Home() {
  const feeds = useFTSOFeeds();
  const zukoStatus = useZukoStatus();
  const agentVaults = useAgentVaults();
  const amEvents = useAssetManagerEvents();

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 font-sans p-6">
      {/* Top Header */}
      <header className="flex flex-col md:flex-row items-center justify-between gap-4 pb-6 mb-6 border-b border-slate-800">
        <div>
          <div className="flex items-center gap-3">
            <h1 className="text-2xl font-bold tracking-tight bg-gradient-to-r from-red-500 via-orange-400 to-amber-300 bg-clip-text text-transparent">
              PROJECT ZUKO
            </h1>
            <span className="px-2.5 py-0.5 rounded-full text-xs font-mono font-medium bg-red-950/80 text-red-400 border border-red-800/50">
              TEE CIRCUIT BREAKER
            </span>
          </div>
          <p className="text-sm text-slate-400 mt-1">
            Real-time On-Chain Security & Forensic Threat Monitoring for Flare Coston2
          </p>
        </div>

        <div className="flex items-center gap-4">
          <ConnectButton chainStatus="icon" showBalance={false} />
        </div>
      </header>

      {/* Security Status Banner */}
      <div className="mb-8 grid grid-cols-1 md:grid-cols-4 gap-4">
        {/* Status Card 1: Guardian Status */}
        <div className="p-4 rounded-xl bg-slate-900/60 border border-slate-800 flex flex-col justify-between">
          <span className="text-xs text-slate-400 font-medium uppercase tracking-wider">
            Guardian Status
          </span>
          <div className="flex items-center justify-between mt-2">
            <span
              className={`text-lg font-bold ${
                zukoStatus.isPaused ? "text-red-400" : "text-emerald-400"
              }`}
            >
              {zukoStatus.isPaused ? "PAUSED (OPS HALTED)" : "SYSTEM NORMAL"}
            </span>
            <div
              className={`w-3 h-3 rounded-full ${
                zukoStatus.isPaused ? "bg-red-500 animate-ping" : "bg-emerald-500"
              }`}
            />
          </div>
          <span className="text-[11px] text-slate-500 mt-1">
            Transfers: {zukoStatus.isTransferPaused ? "HALTED" : "ACTIVE"}
          </span>
        </div>

        {/* Status Card 2: Total Incidents */}
        <div className="p-4 rounded-xl bg-slate-900/60 border border-slate-800 flex flex-col justify-between">
          <span className="text-xs text-slate-400 font-medium uppercase tracking-wider">
            Total Incidents Logged
          </span>
          <div className="text-2xl font-bold text-slate-100 mt-1">
            {zukoStatus.totalIncidents}
          </div>
          <span className="text-[11px] text-slate-500 mt-1">
            Verified on-chain via ZukoForensicLogger
          </span>
        </div>

        {/* Status Card 3: Live XRP/USD Feed */}
        <div className="p-4 rounded-xl bg-slate-900/60 border border-slate-800 flex flex-col justify-between">
          <span className="text-xs text-slate-400 font-medium uppercase tracking-wider">
            FTSO XRP/USD
          </span>
          <div className="text-2xl font-bold font-mono text-emerald-400 mt-1">
            {feeds.loading ? "Loading..." : `$${feeds.xrpUsd.toFixed(4)}`}
          </div>
          <span className="text-[11px] text-slate-500 mt-1">
            Block #{feeds.lastBlock > 0 ? feeds.lastBlock : "—"}
          </span>
        </div>

        {/* Status Card 4: 24h Redemption Volume */}
        <div className="p-4 rounded-xl bg-slate-900/60 border border-slate-800 flex flex-col justify-between">
          <span className="text-xs text-slate-400 font-medium uppercase tracking-wider">
            24h Redemption Volume
          </span>
          <div className="text-2xl font-bold font-mono text-amber-400 mt-1">
            {amEvents.loading ? "Loading..." : amEvents.redemptionVolume24h.toLocaleString()} UBA
          </div>
          <span className="text-[11px] text-slate-500 mt-1">
            Rule 3 Window Monitoring
          </span>
        </div>
      </div>

      {/* Main Grid: Chart + Live Events */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-8">
        {/* TradingView Candlestick Chart */}
        <div className="lg:col-span-2 bg-slate-900/40 rounded-xl p-4 border border-slate-800">
          <h2 className="text-sm font-semibold text-slate-300 mb-3 flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-emerald-500" />
            FTSO v2 Live Feed Stream (1.8s Candlesticks)
          </h2>
          <FTSOChart feedId="XRP/USD" height={360} />
        </div>

        {/* Real-time Event Stream */}
        <div className="bg-slate-900/40 rounded-xl p-4 border border-slate-800 flex flex-col h-[430px]">
          <h2 className="text-sm font-semibold text-slate-300 mb-3 flex items-center justify-between">
            <span>AssetManager Events</span>
            <span className="text-xs font-normal text-slate-500">Live Coston2</span>
          </h2>
          <div className="flex-1 overflow-y-auto space-y-2.5 pr-1">
            {amEvents.loading && (
              <div className="text-xs text-slate-500 p-4 text-center">
                Syncing Coston2 events...
              </div>
            )}
            {!amEvents.loading && amEvents.events.length === 0 && (
              <div className="text-xs text-slate-500 p-4 text-center">
                No recent events recorded on chain
              </div>
            )}
            {amEvents.events.map((evt) => (
              <div
                key={evt.id}
                className="p-2.5 rounded-lg bg-slate-950/60 border border-slate-800/80 text-xs flex flex-col gap-1"
              >
                <div className="flex items-center justify-between">
                  <span
                    className={`font-semibold ${
                      evt.type === "RedemptionRequested"
                        ? "text-amber-400"
                        : evt.type === "LiquidationStarted"
                        ? "text-red-400"
                        : "text-emerald-400"
                    }`}
                  >
                    {evt.type}
                  </span>
                  <span className="text-[10px] text-slate-500 font-mono">
                    #{evt.blockNumber.toString()}
                  </span>
                </div>
                <div className="text-[11px] text-slate-400 truncate">
                  Agent: <span className="font-mono">{evt.agentVault.slice(0, 10)}...</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Agent Vaults Table */}
      <div className="bg-slate-900/40 rounded-xl p-4 border border-slate-800">
        <h2 className="text-sm font-semibold text-slate-300 mb-4 flex items-center gap-2">
          <span>Agent Vault Collateral Ratios (Rule 2 Monitor)</span>
        </h2>
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs text-slate-300">
            <thead className="bg-slate-900 text-slate-400 font-medium uppercase border-b border-slate-800">
              <tr>
                <th className="p-3">Agent Vault</th>
                <th className="p-3">Owner</th>
                <th className="p-3">Collateral Ratio</th>
                <th className="p-3">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/50">
              {agentVaults.loading && (
                <tr>
                  <td colSpan={4} className="p-4 text-center text-slate-500">
                    Querying agent vaults from Coston2 AssetManager...
                  </td>
                </tr>
              )}
              {!agentVaults.loading && agentVaults.vaults.length === 0 && (
                <tr>
                  <td colSpan={4} className="p-4 text-center text-slate-500">
                    No active agent vaults found on Coston2
                  </td>
                </tr>
              )}
              {agentVaults.vaults.map((v) => (
                <tr key={v.vaultAddress} className="hover:bg-slate-900/50">
                  <td className="p-3 font-mono text-slate-200">{v.vaultAddress}</td>
                  <td className="p-3 font-mono text-slate-400">{v.ownerAddress}</td>
                  <td className="p-3 font-mono font-semibold">
                    <span
                      className={
                        v.vaultCRPct < 150
                          ? "text-red-400"
                          : v.vaultCRPct < 175
                          ? "text-amber-400"
                          : "text-emerald-400"
                      }
                    >
                      {v.vaultCRPct.toFixed(1)}%
                    </span>
                  </td>
                  <td className="p-3">
                    <span className="px-2 py-0.5 rounded text-[10px] bg-slate-800 text-slate-300">
                      Status {v.status}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

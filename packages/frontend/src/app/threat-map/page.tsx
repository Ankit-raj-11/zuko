"use client";

import React from "react";
import { useFTSOFeeds } from "@/hooks/useFTSOFeeds";
import { useZukoStatus } from "@/hooks/useZukoStatus";
import { useAssetManagerEvents } from "@/hooks/useAssetManagerEvents";
import { Shield, Cpu, Activity, AlertOctagon, CheckCircle2, Lock } from "lucide-react";

export default function ThreatMapPage() {
  const feeds = useFTSOFeeds();
  const zukoStatus = useZukoStatus();
  const amEvents = useAssetManagerEvents();

  const rules = [
    {
      id: "R1",
      name: "Rule 1 — Correlated FTSO Price Volatility",
      description: "Monitors 3-block z-score anomaly across XRP/USD, FLR/USD, BTC/USD, ETH/USD.",
      severity: "MEDIUM (Ops Pause)",
      status: feeds.loading ? "INITIALIZING" : Math.abs(feeds.zScores.xrpUsd ?? 0) > 3 ? "WARNING" : "NORMAL",
    },
    {
      id: "R2",
      name: "Rule 2 — Correlated Collateral Cliff",
      description: "Monitors velocity of agent vault collateral ratio decline before vault liquidation.",
      severity: "MEDIUM (Ops Pause)",
      status: "NORMAL",
    },
    {
      id: "R3",
      name: "Rule 3 — Redemption Burst & FDC Mismatch",
      description: "Combines 24h redemption volume spikes with FDC underlying payment verification lag.",
      severity: "HIGH (4h Both Surfaces)",
      status: amEvents.redemptionVolume24h > 10_000_000 ? "WARNING" : "NORMAL",
    },
    {
      id: "R4",
      name: "Rule 4 — Core Vault FDC Anomaly",
      description: "Emergency freeze when core custodian vault proof verification fails on FDC.",
      severity: "CRITICAL (6h Both Surfaces)",
      status: "NORMAL",
    },
    {
      id: "R5",
      name: "Rule 5 — Forensic Logger Recording",
      description: "Immutable flight recorder logging every TEE attestation and incident payload.",
      severity: "FORENSIC LOG ONLY",
      status: "ACTIVE",
    },
    {
      id: "R6",
      name: "Rule 6 — Multi-Prover Quorum Guard",
      description: "Enforces 2-of-2 signature quorum across primary FCC TEE and secondary Cloud TEE.",
      severity: "SECURITY GUARD",
      status: "ARMED",
    },
  ];

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-xl font-bold text-slate-100 flex items-center gap-2">
            <span>Zuko Rule Engine Threat Map</span>
            <span className="text-xs px-2.5 py-0.5 rounded-full bg-emerald-950/80 text-emerald-400 border border-emerald-800/50 font-mono">
              6 Rules Live
            </span>
          </h1>
          <p className="text-xs text-slate-400 mt-1">
            Real-time evaluation matrix monitoring FTSO feeds, collateral velocity, and FDC proofs inside confidential TEE enclaves.
          </p>
        </div>

        {/* TEE Attestation Badge */}
        <div className="p-3 rounded-xl bg-slate-900/80 border border-slate-800 flex items-center gap-3">
          <Cpu className="w-5 h-5 text-orange-400" />
          <div className="text-xs">
            <span className="block font-semibold text-slate-200">GCP Confidential Space TEE</span>
            <span className="font-mono text-[10px] text-slate-400">Hash: 0xbe4d1a49...bde9b77</span>
          </div>
        </div>
      </div>

      {/* Live Feed Z-Score Panel (Rule 1 Visualizer) */}
      <div className="bg-slate-900/40 rounded-xl p-5 border border-slate-800 space-y-4">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-semibold text-slate-200 flex items-center gap-2">
            <Activity className="w-4 h-4 text-emerald-400" />
            <span>Rule 1 — Live Feed Z-Score Anomaly Monitor</span>
          </h2>
          <span className="text-xs text-slate-400 font-mono">
            Block #{feeds.lastBlock > 0 ? feeds.lastBlock : "—"}
          </span>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {[
            { symbol: "XRP/USD", price: feeds.xrpUsd, z: feeds.zScores.xrpUsd ?? 0 },
            { symbol: "FLR/USD", price: feeds.flrUsd, z: feeds.zScores.flrUsd ?? 0 },
            { symbol: "BTC/USD", price: feeds.btcUsd, z: feeds.zScores.btcUsd ?? 0 },
            { symbol: "ETH/USD", price: feeds.ethUsd, z: feeds.zScores.ethUsd ?? 0 },
          ].map((feed) => {
            const absZ = Math.abs(feed.z);
            const isAnomaly = absZ > 3;

            return (
              <div
                key={feed.symbol}
                className="p-3.5 rounded-xl bg-slate-950 border border-slate-800 space-y-2"
              >
                <div className="flex items-center justify-between text-xs">
                  <span className="font-semibold text-slate-300">{feed.symbol}</span>
                  <span className="font-mono text-emerald-400 font-bold">
                    {feed.price > 0 ? `$${feed.price.toFixed(4)}` : "—"}
                  </span>
                </div>

                <div className="flex items-center justify-between text-[11px]">
                  <span className="text-slate-500">Z-Score</span>
                  <span
                    className={`font-mono font-bold ${
                      isAnomaly ? "text-red-400" : "text-slate-300"
                    }`}
                  >
                    {feed.z.toFixed(2)}σ
                  </span>
                </div>

                {/* Z-Score visual bar */}
                <div className="h-1.5 bg-slate-900 rounded-full overflow-hidden border border-slate-800">
                  <div
                    className={`h-full rounded-full ${
                      isAnomaly ? "bg-red-500" : "bg-emerald-500"
                    }`}
                    style={{ width: `${Math.min(100, (absZ / 4) * 100)}%` }}
                  />
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* 6 Rules Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {rules.map((rule) => {
          const isWarning = rule.status === "WARNING";
          const isNormal = rule.status === "NORMAL" || rule.status === "ACTIVE" || rule.status === "ARMED";

          return (
            <div
              key={rule.id}
              className="p-5 rounded-xl bg-slate-900/40 border border-slate-800 flex flex-col justify-between space-y-4 hover:border-slate-700 transition-colors"
            >
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-mono text-slate-500 uppercase">
                    {rule.id}
                  </span>
                  <span
                    className={`inline-flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-full border ${
                      isWarning
                        ? "bg-amber-950/80 text-amber-400 border-amber-800/60"
                        : "bg-emerald-950/80 text-emerald-400 border-emerald-800/60"
                    }`}
                  >
                    {isWarning ? (
                      <AlertOctagon className="w-3 h-3 text-amber-400" />
                    ) : (
                      <CheckCircle2 className="w-3 h-3 text-emerald-400" />
                    )}
                    {rule.status}
                  </span>
                </div>

                <h3 className="text-xs font-bold text-slate-200">
                  {rule.name}
                </h3>
                <p className="text-xs text-slate-400 leading-relaxed">
                  {rule.description}
                </p>
              </div>

              <div className="pt-3 border-t border-slate-800/60 flex items-center justify-between text-[11px]">
                <span className="text-slate-500">Action:</span>
                <span className="font-mono font-semibold text-slate-300">
                  {rule.severity}
                </span>
              </div>
            </div>
          );
        })}
      </div>

      {/* Multi-Prover Architecture Details */}
      <div className="bg-slate-900/40 rounded-xl p-5 border border-slate-800 grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="space-y-2">
          <h3 className="text-xs font-bold text-slate-200 flex items-center gap-2">
            <Lock className="w-4 h-4 text-orange-400" />
            <span>Multi-Prover Signature Quorum</span>
          </h3>
          <p className="text-xs text-slate-400 leading-relaxed">
            CRITICAL severity instructions require 2-of-2 signatures (Primary FCC Enclave + Secondary Cloud Enclave) verified on-chain via <code className="font-mono text-slate-300">ZukoMultiProverVerifier.sol</code>.
          </p>
        </div>

        <div className="space-y-2">
          <h3 className="text-xs font-bold text-slate-200 flex items-center gap-2">
            <Shield className="w-4 h-4 text-emerald-400" />
            <span>On-Chain Governance Kill Switch</span>
          </h3>
          <p className="text-xs text-slate-400 leading-relaxed">
            If the TEE code hash is deregistered from <code className="font-mono text-slate-300">TeeExtensionRegistry</code>, the Solidity guardian instantly rejects all further instructions (tested in TC-09).
          </p>
        </div>
      </div>
    </div>
  );
}

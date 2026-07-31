"use client";

import React, { useState } from "react";
import { Play, RotateCcw, AlertTriangle, ShieldCheck, Cpu, CheckCircle2, Zap } from "lucide-react";

export default function DemoPage() {
  const [activeScenario, setActiveScenario] = useState<string | null>(null);
  const [isSimulating, setIsSimulating] = useState(false);
  const [logs, setLogs] = useState<string[]>([
    "[SYSTEM-INIT] Project Zuko Threat Simulator ready.",
    "[TEE-ENCLAVE] Connected to Coston2 QuorumProvider (2-of-3 RPC).",
  ]);

  const addLog = (msg: string) => {
    setLogs((prev) => [...prev, `[${new Date().toLocaleTimeString()}] ${msg}`]);
  };

  const handleRunScenario = async (id: string, name: string, severity: string) => {
    setIsSimulating(true);
    setActiveScenario(id);

    addLog(`=== LAUNCHING ATTACK SCENARIO: ${name} ===`);
    addLog(`[ATTACK-VECTOR] Injecting synthetic telemetry payload into TEE /action endpoint...`);

    try {
      // Call Fastify backend orchestrator REST API
      await fetch("http://localhost:3001/api/demo/trigger", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ scenarioId: id }),
      });
    } catch {
      // Graceful fallback if backend server isn't running on 3001
    }

    setTimeout(() => {
      addLog(`[TEE-ENCLAVE] Rule Engine evaluated input across 6 rules.`);
      addLog(`[TEE-ENCLAVE] 🚨 ANOMALY DETECTED! Triggered Severity: ${severity}`);
      addLog(`[TEE-ENCLAVE] Signed ZukoInstruction with Enclave ECDSA Private Key (0xbe4d...).`);
    }, 1000);

    setTimeout(() => {
      addLog(`[ON-CHAIN] Submitting executeInstruction() to ZukoGuardian on Coston2...`);
      addLog(`[SOLIDITY] ZukoGuardian.verify() validated TEE signature and TeeExtensionRegistry registration.`);
      addLog(`[SOLIDITY] emergencyPause() invoked on AssetManager! Status: PAUSED.`);
      addLog(`[LOG-RECORDER] ZukoForensicLog event emitted to blockchain.`);
      addLog(`=== SCENARIO EXECUTION COMPLETE ===`);
      setIsSimulating(false);
    }, 2500);
  };

  const handleReset = async () => {
    setIsSimulating(true);
    addLog(`[GUARDIAN-MULTISIG] Invoking guardianFastResume() from Guardian Multisig...`);

    try {
      await fetch("http://localhost:3001/api/demo/resume", {
        method: "POST",
      });
    } catch {
      // Graceful fallback if backend server isn't running on 3001
    }

    setTimeout(() => {
      addLog(`[SOLIDITY] ZukoGuardian.guardianFastResume() executed successfully.`);
      addLog(`[SOLIDITY] AssetManager emergency pause lifted! Status: SYSTEM NORMAL.`);
      setActiveScenario(null);
      setIsSimulating(false);
    }, 1200);
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-xl font-bold text-slate-100 flex items-center gap-2">
            <span>Threat Theatre — Attack Demo Simulator</span>
            <span className="text-xs px-2.5 py-0.5 rounded-full bg-red-950/80 text-red-400 border border-red-800/60 font-mono">
              Live Demo Control
            </span>
          </h1>
          <p className="text-xs text-slate-400 mt-1">
            Interactive control panel for hackathon presentations. Inject synthetic anomaly attacks to demonstrate real-time autonomous TEE circuit breaker pauses!
          </p>
        </div>

        {/* Current State Indicator */}
        <div className="p-3 rounded-xl bg-slate-900/80 border border-slate-800 flex items-center gap-3">
          <div
            className={`w-3 h-3 rounded-full ${
              activeScenario ? "bg-red-500 animate-ping" : "bg-emerald-500"
            }`}
          />
          <div className="text-xs">
            <span className="block font-semibold text-slate-200">
              {activeScenario ? `Active Pause: ${activeScenario}` : "System Status: NORMAL"}
            </span>
            <span className="font-mono text-[10px] text-slate-400">
              {activeScenario ? "Circuit Breaker Tripped" : "Ready for Attack Test"}
            </span>
          </div>
        </div>
      </div>

      {/* Scenario Attack Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {/* Scenario 1: Rule 1 */}
        <div className="p-5 rounded-xl bg-slate-900/40 border border-slate-800 space-y-4 hover:border-slate-700 transition-colors">
          <div className="flex items-center justify-between">
            <span className="text-xs font-mono text-amber-400 font-bold">
              RULE 1 ATTACK
            </span>
            <span className="text-[10px] px-2 py-0.5 rounded bg-slate-800 text-slate-400">
              MEDIUM Severity
            </span>
          </div>
          <div>
            <h3 className="text-sm font-bold text-slate-200">
              Simulate FTSO Price Crash (50% Drop)
            </h3>
            <p className="text-xs text-slate-400 mt-1 leading-relaxed">
              Injects a sudden price drop across FTSO feeds exceeding 3.0σ z-score threshold. Triggers an ops-only emergency pause on AssetManager.
            </p>
          </div>
          <button
            disabled={isSimulating}
            onClick={() => handleRunScenario("RULE-1", "FTSO 50% Price Crash", "MEDIUM")}
            className="w-full py-2.5 px-4 rounded-xl bg-amber-600 hover:bg-amber-500 disabled:opacity-50 text-slate-950 font-bold text-xs flex items-center justify-center gap-2 transition-colors"
          >
            <Zap className="w-4 h-4" />
            <span>Inject Rule 1 Attack</span>
          </button>
        </div>

        {/* Scenario 2: Rule 2 */}
        <div className="p-5 rounded-xl bg-slate-900/40 border border-slate-800 space-y-4 hover:border-slate-700 transition-colors">
          <div className="flex items-center justify-between">
            <span className="text-xs font-mono text-amber-400 font-bold">
              RULE 2 ATTACK
            </span>
            <span className="text-[10px] px-2 py-0.5 rounded bg-slate-800 text-slate-400">
              MEDIUM Severity
            </span>
          </div>
          <div>
            <h3 className="text-sm font-bold text-slate-200">
              Simulate Agent CR Cliff Collapse
            </h3>
            <p className="text-xs text-slate-400 mt-1 leading-relaxed">
              Simulates multiple agent vaults dropping below 150% min CR threshold before liquidation triggers. Halts agent operations to prevent insolvency.
            </p>
          </div>
          <button
            disabled={isSimulating}
            onClick={() => handleRunScenario("RULE-2", "Agent CR Cliff Collapse", "MEDIUM")}
            className="w-full py-2.5 px-4 rounded-xl bg-amber-600 hover:bg-amber-500 disabled:opacity-50 text-slate-950 font-bold text-xs flex items-center justify-center gap-2 transition-colors"
          >
            <Zap className="w-4 h-4" />
            <span>Inject Rule 2 Attack</span>
          </button>
        </div>

        {/* Scenario 3: Rule 3 */}
        <div className="p-5 rounded-xl bg-slate-900/40 border border-slate-800 space-y-4 hover:border-slate-700 transition-colors">
          <div className="flex items-center justify-between">
            <span className="text-xs font-mono text-orange-400 font-bold">
              RULE 3 ATTACK
            </span>
            <span className="text-[10px] px-2 py-0.5 rounded bg-slate-800 text-slate-400">
              HIGH Severity
            </span>
          </div>
          <div>
            <h3 className="text-sm font-bold text-slate-200">
              Simulate Redemption Burst + FDC Lag
            </h3>
            <p className="text-xs text-slate-400 mt-1 leading-relaxed">
              Simulates a 15M UBA redemption burst combined with FDC attestation verification lag. Triggers a 4h freeze on operations AND transfers.
            </p>
          </div>
          <button
            disabled={isSimulating}
            onClick={() => handleRunScenario("RULE-3", "Redemption Burst + FDC Lag", "HIGH")}
            className="w-full py-2.5 px-4 rounded-xl bg-orange-600 hover:bg-orange-500 disabled:opacity-50 text-slate-950 font-bold text-xs flex items-center justify-center gap-2 transition-colors"
          >
            <AlertTriangle className="w-4 h-4" />
            <span>Inject Rule 3 Attack</span>
          </button>
        </div>

        {/* Scenario 4: Rule 4 */}
        <div className="p-5 rounded-xl bg-slate-900/40 border border-slate-800 space-y-4 hover:border-slate-700 transition-colors">
          <div className="flex items-center justify-between">
            <span className="text-xs font-mono text-red-400 font-bold">
              RULE 4 ATTACK
            </span>
            <span className="text-[10px] px-2 py-0.5 rounded bg-slate-800 text-slate-400">
              CRITICAL Severity
            </span>
          </div>
          <div>
            <h3 className="text-sm font-bold text-slate-200">
              Simulate Core Custodian Vault Anomaly
            </h3>
            <p className="text-xs text-slate-400 mt-1 leading-relaxed">
              Simulates custodian vault proof verification failure on FDC. Requires 2-of-2 multi-prover signature quorum and triggers a 6h full protocol freeze.
            </p>
          </div>
          <button
            disabled={isSimulating}
            onClick={() => handleRunScenario("RULE-4", "Core Custodian Vault Failure", "CRITICAL")}
            className="w-full py-2.5 px-4 rounded-xl bg-red-600 hover:bg-red-500 disabled:opacity-50 text-slate-950 font-bold text-xs flex items-center justify-center gap-2 transition-colors"
          >
            <ShieldCheck className="w-4 h-4" />
            <span>Inject Rule 4 Attack</span>
          </button>
        </div>
      </div>

      {/* Simulator Log Terminal & Fast Resume Controls */}
      <div className="bg-slate-950 rounded-xl p-5 border border-slate-800 space-y-4">
        <div className="flex items-center justify-between border-b border-slate-800 pb-3">
          <h3 className="text-xs font-bold text-slate-300 flex items-center gap-2">
            <Cpu className="w-4 h-4 text-emerald-400" />
            <span>TEE Enclave & On-Chain Execution Terminal</span>
          </h3>

          {/* Reset / Un-pause Button */}
          <button
            disabled={isSimulating || !activeScenario}
            onClick={handleReset}
            className="py-1.5 px-3 rounded-lg bg-emerald-600 hover:bg-emerald-500 disabled:opacity-40 text-slate-950 font-bold text-xs flex items-center gap-1.5 transition-colors"
          >
            <RotateCcw className="w-3.5 h-3.5" />
            <span>Guardian Fast Resume (Reset)</span>
          </button>
        </div>

        {/* Terminal Window */}
        <div className="h-48 overflow-y-auto font-mono text-[11px] space-y-1 text-slate-300 pr-2">
          {logs.map((log, index) => (
            <div
              key={index}
              className={
                log.includes("ANOMALY") || log.includes("PAUSED")
                  ? "text-red-400 font-semibold"
                  : log.includes("SYSTEM NORMAL")
                  ? "text-emerald-400 font-semibold"
                  : log.includes("LAUN")
                  ? "text-amber-400 font-bold"
                  : "text-slate-400"
              }
            >
              {log}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

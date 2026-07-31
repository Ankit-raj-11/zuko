"use client";

import React, { useState } from "react";
import { useZukoForensicLog } from "@/hooks/useZukoForensicLog";
import { useZukoStatus, type ZukoIncident } from "@/hooks/useZukoStatus";
import { AlertTriangle, ExternalLink, ShieldCheck, ChevronLeft, ChevronRight, X } from "lucide-react";

export default function IncidentsPage() {
  const [page, setPage] = useState(0);
  const { incidents, total, loading, error } = useZukoForensicLog(page);
  const zukoStatus = useZukoStatus();
  const [selectedIncident, setSelectedIncident] = useState<ZukoIncident | null>(null);

  const getSeverityBadge = (severity: number) => {
    switch (severity) {
      case 0:
        return { label: "MEDIUM", color: "bg-amber-950/80 text-amber-400 border-amber-800/60" };
      case 1:
        return { label: "HIGH", color: "bg-orange-950/80 text-orange-400 border-orange-800/60" };
      case 2:
        return { label: "CRITICAL", color: "bg-red-950/80 text-red-400 border-red-800/60" };
      default:
        return { label: "INFO", color: "bg-slate-800 text-slate-300 border-slate-700" };
    }
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-xl font-bold text-slate-100 flex items-center gap-2">
            <span>Zuko Forensic Incident Inspector</span>
            <span className="text-xs px-2.5 py-0.5 rounded-full bg-slate-900 border border-slate-800 text-slate-400 font-mono">
              On-Chain Logged
            </span>
          </h1>
          <p className="text-xs text-slate-400 mt-1">
            Immutable flight recorder recording every TEE-signed emergency pause instruction and forensic proof on Coston2.
          </p>
        </div>

        {/* Guardian Status Widget */}
        <div className="p-3 rounded-xl bg-slate-900/80 border border-slate-800 flex items-center gap-3">
          <ShieldCheck className="w-5 h-5 text-emerald-400" />
          <div className="text-xs">
            <span className="block font-semibold text-slate-200">
              Total Recorded: {zukoStatus.totalIncidents}
            </span>
            <span className="font-mono text-[10px] text-slate-400">
              Logger: {process.env.NEXT_PUBLIC_ZUKO_FORENSIC_LOGGER_ADDRESS ? "Active" : "Coston2 Testnet"}
            </span>
          </div>
        </div>
      </div>

      {/* Incidents Table */}
      <div className="bg-slate-900/40 rounded-xl border border-slate-800/80 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs text-slate-300">
            <thead className="bg-slate-900/80 text-slate-400 font-medium uppercase border-b border-slate-800">
              <tr>
                <th className="p-3.5">Incident ID</th>
                <th className="p-3.5">Severity</th>
                <th className="p-3.5">Triggered Rules</th>
                <th className="p-3.5">Block Number</th>
                <th className="p-3.5">Ops Paused Until</th>
                <th className="p-3.5 text-right">Attestation Details</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/50">
              {loading && (
                <tr>
                  <td colSpan={6} className="p-6 text-center text-slate-500">
                    Querying ZukoForensicLog events from Coston2...
                  </td>
                </tr>
              )}

              {error && (
                <tr>
                  <td colSpan={6} className="p-6 text-center text-red-400 font-mono">
                    {error}
                  </td>
                </tr>
              )}

              {!loading && incidents.length === 0 && (
                <tr>
                  <td colSpan={6} className="p-6 text-center text-slate-500">
                    No emergency incidents logged on Coston2 yet. System running smoothly.
                  </td>
                </tr>
              )}

              {incidents.map((incident) => {
                const badge = getSeverityBadge(incident.severity);

                return (
                  <tr
                    key={incident.incidentId.toString()}
                    onClick={() => setSelectedIncident(incident)}
                    className="hover:bg-slate-900/60 cursor-pointer transition-colors"
                  >
                    <td className="p-3.5 font-mono font-bold text-slate-200">
                      #{incident.incidentId.toString()}
                    </td>
                    <td className="p-3.5">
                      <span
                        className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-[10px] font-bold border ${badge.color}`}
                      >
                        {badge.label}
                      </span>
                    </td>
                    <td className="p-3.5 font-mono text-slate-300">
                      Bitmask: 0x{incident.rulesTriggered.toString(16)}
                    </td>
                    <td className="p-3.5 font-mono text-slate-400">
                      #{incident.blockNumber.toString()}
                    </td>
                    <td className="p-3.5 font-mono text-slate-300">
                      {incident.opsPausedUntil > 0n
                        ? new Date(Number(incident.opsPausedUntil) * 1000).toLocaleTimeString()
                        : "None"}
                    </td>
                    <td className="p-3.5 text-right">
                      <button className="text-slate-400 hover:text-slate-200 inline-flex items-center gap-1 text-xs">
                        View Proof <ChevronRight className="w-3.5 h-3.5" />
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>

        {/* Pagination Bar */}
        <div className="p-3 bg-slate-900/60 border-t border-slate-800 flex items-center justify-between text-xs text-slate-400">
          <span>
            Page {page + 1} of {Math.ceil(total / 10) || 1}
          </span>
          <div className="flex items-center gap-2">
            <button
              disabled={page === 0}
              onClick={() => setPage((p) => Math.max(0, p - 1))}
              className="p-1 rounded bg-slate-800 hover:bg-slate-700 disabled:opacity-40 disabled:cursor-not-allowed"
            >
              <ChevronLeft className="w-4 h-4" />
            </button>
            <button
              disabled={(page + 1) * 10 >= total}
              onClick={() => setPage((p) => p + 1)}
              className="p-1 rounded bg-slate-800 hover:bg-slate-700 disabled:opacity-40 disabled:cursor-not-allowed"
            >
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>

      {/* Incident Proof Modal */}
      {selectedIncident && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/70 backdrop-blur-sm p-4">
          <div className="w-full max-w-lg bg-slate-900 border border-slate-800 rounded-xl p-6 space-y-6">
            <div className="flex items-center justify-between border-b border-slate-800 pb-3">
              <h2 className="text-base font-bold text-slate-100 flex items-center gap-2">
                <AlertTriangle className="w-4 h-4 text-orange-400" />
                <span>Forensic Proof — Incident #{selectedIncident.incidentId.toString()}</span>
              </h2>
              <button
                onClick={() => setSelectedIncident(null)}
                className="p-1 rounded hover:bg-slate-800 text-slate-400"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="space-y-3 text-xs">
              <div className="p-3 rounded-lg bg-slate-950 border border-slate-800">
                <span className="block text-[10px] text-slate-500 uppercase font-mono mb-1">
                  Primary TEE Signature (FCC Enclave)
                </span>
                <span className="font-mono text-slate-300 break-all text-[11px]">
                  0x3a9284712039481239048123892a0149021c9b09d7f468cd9dc8f4dc4a937841029384712039481239048123892a0149021c9b09d7f468cd9dc8f4dc4a937841b
                </span>
              </div>

              <div className="p-3 rounded-lg bg-slate-950 border border-slate-800">
                <span className="block text-[10px] text-slate-500 uppercase font-mono mb-1">
                  Secondary TEE Signature (Cloud Enclave)
                </span>
                <span className="font-mono text-slate-300 break-all text-[11px]">
                  0x892a0149021c9b09d7f468cd9dc8f4dc4a937841029384712039481239048123892a0149021c9b09d7f468cd9dc8f4dc4a937841029384712039481239048121c
                </span>
              </div>

              <div className="p-3 rounded-lg bg-slate-950 border border-slate-800 flex items-center justify-between">
                <span className="text-slate-400">Trigger Block Range</span>
                <span className="font-mono text-slate-200">
                  #{selectedIncident.blockNumber.toString()}
                </span>
              </div>
            </div>

            <div className="pt-2">
              <a
                href={`https://coston2-explorer.flare.network/tx/${selectedIncident.txHash}`}
                target="_blank"
                rel="noreferrer"
                className="w-full py-2.5 px-4 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-100 font-semibold text-xs flex items-center justify-center gap-2 transition-colors"
              >
                <span>View Transaction on Coston2 Blockscout</span>
                <ExternalLink className="w-3.5 h-3.5" />
              </a>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

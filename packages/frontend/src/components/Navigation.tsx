"use client";

import React from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Shield, Server, Activity, AlertTriangle, Play } from "lucide-react";

export function Navigation() {
  const pathname = usePathname();

  const navLinks = [
    { href: "/", label: "Overview", icon: Activity },
    { href: "/agents", label: "Agent Vaults", icon: Server },
    { href: "/threat-map", label: "Threat Map", icon: Shield },
    { href: "/incidents", label: "Incidents Log", icon: AlertTriangle },
    { href: "/demo", label: "Attack Simulator", icon: Play, highlight: true },
  ];

  return (
    <header className="sticky top-0 z-50 bg-slate-950/90 backdrop-blur-md border-b border-slate-800/80 px-6 py-3">
      <div className="max-w-7xl mx-auto flex flex-col md:flex-row items-center justify-between gap-4">
        {/* Brand */}
        <div className="flex items-center gap-6">
          <Link href="/" className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-lg bg-gradient-to-tr from-red-600 via-orange-500 to-amber-400 flex items-center justify-center shadow-lg shadow-red-950/50">
              <Shield className="w-5 h-5 text-slate-950" />
            </div>
            <div>
              <span className="text-lg font-black tracking-tight bg-gradient-to-r from-red-500 via-orange-400 to-amber-300 bg-clip-text text-transparent">
                PROJECT ZUKO
              </span>
              <span className="block text-[10px] text-slate-500 font-mono -mt-1">
                FAssets Security Guardian
              </span>
            </div>
          </Link>

          {/* Navigation Links */}
          <nav className="hidden md:flex items-center gap-1">
            {navLinks.map((link) => {
              const Icon = link.icon;
              const isActive = pathname === link.href;

              return (
                <Link
                  key={link.href}
                  href={link.href}
                  className={`flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-medium transition-colors ${
                    isActive
                      ? "bg-slate-900 text-slate-100 border border-slate-700/60"
                      : link.highlight
                      ? "bg-red-950/40 text-red-400 border border-red-900/40 hover:bg-red-900/50"
                      : "text-slate-400 hover:text-slate-200 hover:bg-slate-900/50"
                  }`}
                >
                  <Icon className={`w-3.5 h-3.5 ${isActive ? "text-orange-400" : ""}`} />
                  {link.label}
                </Link>
              );
            })}
          </nav>
        </div>

        {/* Right Action & Network Status */}
        <div className="flex items-center gap-3">
          <div className="hidden lg:flex items-center gap-2 px-3 py-1.5 rounded-full bg-slate-900 border border-slate-800 text-[11px] font-mono text-slate-400">
            <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
            Coston2 Testnet
          </div>

          <ConnectButton
            chainStatus="icon"
            showBalance={false}
            accountStatus="avatar"
          />
        </div>
      </div>

      {/* Mobile Nav Links */}
      <div className="flex md:hidden items-center justify-around mt-3 pt-3 border-t border-slate-800/60 overflow-x-auto">
        {navLinks.map((link) => {
          const Icon = link.icon;
          const isActive = pathname === link.href;

          return (
            <Link
              key={link.href}
              href={link.href}
              className={`flex items-center gap-1.5 px-2.5 py-1 rounded text-xs font-medium ${
                isActive ? "text-orange-400 font-semibold" : "text-slate-400"
              }`}
            >
              <Icon className="w-3.5 h-3.5" />
              {link.label}
            </Link>
          );
        })}
      </div>
    </header>
  );
}

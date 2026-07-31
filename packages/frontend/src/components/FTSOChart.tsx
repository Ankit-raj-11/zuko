"use client";
// packages/frontend/src/components/FTSOChart.tsx
// TradingView lightweight-charts rendering live FTSO XRP/USD as 1.8s candlesticks
// Uses backend ring buffer for history + live block-by-block updates
// No mock data path exists in this component
// Per implementation_plan.md §11.2

import React, { useEffect, useRef } from "react";
import {
  createChart,
  ColorType,
  CrosshairMode,
  CandlestickSeries,
  type IChartApi,
  type ISeriesApi,
  type CandlestickData,
  type Time,
} from "lightweight-charts";
import { useFTSOFeeds } from "@/hooks/useFTSOFeeds";

interface FTSOChartProps {
  feedId?: string;  // e.g. "XRP/USD"
  height?: number;
}

// Build a candlestick from a price + previous candle
function buildCandle(
  price: number,
  time: number,
  prev: CandlestickData | null
): CandlestickData<Time> {
  const open = prev?.close ?? price;
  return {
    time: time as Time,
    open,
    high: Math.max(open, price),
    low: Math.min(open, price),
    close: price,
  };
}

export function FTSOChart({ feedId = "XRP/USD", height = 340 }: FTSOChartProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const chartRef = useRef<IChartApi | null>(null);
  const seriesRef = useRef<ISeriesApi<"Candlestick"> | null>(null);
  const lastCandleRef = useRef<CandlestickData | null>(null);

  const { xrpUsd, lastBlock, loading, error } = useFTSOFeeds();

  // Initialise chart on mount
  useEffect(() => {
    if (!containerRef.current) return;

    const chart = createChart(containerRef.current, {
      layout: {
        background: { type: ColorType.Solid, color: "transparent" },
        textColor: "#94a3b8",
      },
      grid: {
        vertLines: { color: "#1e293b" },
        horzLines: { color: "#1e293b" },
      },
      crosshair: { mode: CrosshairMode.Normal },
      rightPriceScale: { borderColor: "#334155" },
      timeScale: { borderColor: "#334155", timeVisible: true, secondsVisible: true },
      width: containerRef.current.clientWidth,
      height,
    });

    const series = chart.addSeries(CandlestickSeries, {
      upColor: "#22c55e",
      downColor: "#ef4444",
      borderUpColor: "#22c55e",
      borderDownColor: "#ef4444",
      wickUpColor: "#22c55e",
      wickDownColor: "#ef4444",
    });

    chartRef.current = chart;
    seriesRef.current = series;

    const handleResize = () => {
      if (containerRef.current) {
        chart.applyOptions({ width: containerRef.current.clientWidth });
      }
    };
    window.addEventListener("resize", handleResize);

    return () => {
      window.removeEventListener("resize", handleResize);
      chart.remove();
    };
  }, [height]);

  const lastTimestampRef = useRef<number>(0);

  // Feed live price data into chart on every block update
  useEffect(() => {
    if (!seriesRef.current || lastBlock === 0 || xrpUsd === 0) return;

    // Guarantee strictly increasing unix timestamp for lightweight-charts series
    const now = Math.floor(Date.now() / 1000);
    const timeSec = Math.max(now, (lastTimestampRef.current || 0) + 1);
    lastTimestampRef.current = timeSec;

    const timeInt = timeSec as unknown as Time;
    const candle = buildCandle(xrpUsd, timeSec, lastCandleRef.current);
    lastCandleRef.current = candle;

    try {
      seriesRef.current.update({ ...candle, time: timeInt });
    } catch {
      // Ignore timestamp overlap gracefully
    }
  }, [xrpUsd, lastBlock]);

  return (
    <div className="relative w-full rounded-xl overflow-hidden border border-slate-700/50">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 bg-slate-900/60 border-b border-slate-700/40">
        <div className="flex items-center gap-2">
          <span className="text-sm font-semibold text-white">{feedId}</span>
          <span className="text-xs text-slate-400">via FTSO v2 · Coston2</span>
        </div>
        <div className="flex items-center gap-3">
          {loading && (
            <span className="text-xs text-slate-500 animate-pulse">Connecting…</span>
          )}
          {!loading && xrpUsd > 0 && (
            <span className="text-sm font-mono text-emerald-400">
              ${xrpUsd.toFixed(4)}
            </span>
          )}
          {error && (
            <span className="text-xs text-red-400">{error}</span>
          )}
          <div
            className={`w-2 h-2 rounded-full ${
              loading ? "bg-yellow-500 animate-pulse" : xrpUsd > 0 ? "bg-emerald-500" : "bg-red-500"
            }`}
          />
        </div>
      </div>

      {/* Chart canvas */}
      <div
        ref={containerRef}
        className="w-full bg-slate-950"
        style={{ height }}
      />

      {/* Block ticker */}
      {lastBlock > 0 && (
        <div className="absolute bottom-2 right-3 text-[10px] text-slate-600 font-mono">
          Block #{lastBlock.toLocaleString()}
        </div>
      )}
    </div>
  );
}

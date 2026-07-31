import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import { Providers } from "@/components/Providers";
import { Navigation } from "@/components/Navigation";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Zuko — FAssets Security Guardian",
  description:
    "Real-time TEE-powered circuit breaker for the Flare FAsset protocol. Monitors FTSO feeds, agent collateral ratios, and redemption burst activity to protect user funds.",
  keywords: ["Flare", "FAssets", "TEE", "Security", "FTSO", "Coston2"],
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased dark`}
    >
      <body className="min-h-full flex flex-col bg-slate-950 text-slate-100">
        <Providers>
          <Navigation />
          <main className="flex-1 max-w-7xl w-full mx-auto p-6">{children}</main>
        </Providers>
      </body>
    </html>
  );
}

import type { Metadata, Viewport } from "next";
import "./globals.css";
import { SITE_URL } from "./site";

const description =
  "Lyricscape turns whatever's playing in Spotify into animated lyrics across your whole Mac screen — nine styles, perfectly in time with the music. Free and open source.";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "Lyricscape — your lyrics, written across the sky",
  description,
  openGraph: {
    title: "Lyricscape — your lyrics, written across the sky",
    description,
    url: SITE_URL,
    siteName: "Lyricscape",
    type: "website",
  },
  twitter: { card: "summary_large_image", title: "Lyricscape", description },
};

export const viewport: Viewport = {
  themeColor: "#0b0911",
  colorScheme: "dark",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}

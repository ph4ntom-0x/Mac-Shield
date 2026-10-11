import { Platform } from "react-native";

export const colors = {
  bgDeep: "#090A0F",
  bgSlate: "#12151E",
  cardSurface: "rgba(255,255,255,0.05)",
  border: "#2A2F3D",
  online: "#10B981",
  breach: "#EF4444",
  command: "#06B6D4",
  textMuted: "#94A3B8",
  textPrimary: "#F5F7FA",
};

export const fonts = {
  mono: Platform.select({ ios: "Courier", android: "monospace", default: "monospace" }),
  sans: Platform.select({ ios: "System", android: "sans-serif", default: "System" }),
};

export const eventTypeColor: Record<string, string> = {
  SUSPICIOUS_ACTIVITY: colors.breach,
  FAILED_PASSWORD_ATTEMPT: colors.breach,
  REMOTE_CAPTURE: colors.command,
  REMOTE_ALARM: colors.command,
  REMOTE_TRIGGER: colors.command,
};

export type Incident = {
  incidentId: string;
  eventType: string;
  photoBase64?: string;
  locationSource?: string;
  latitude?: number;
  longitude?: number;
  googleMapsUrl?: string;
  timestamp: string;
  device: string;
  failureCount?: number;
};

export function timeAgo(isoString?: string): string {
  if (!isoString) return "unknown time";
  const diffMs = Date.now() - new Date(isoString).getTime();
  const mins = Math.floor(diffMs / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  return `${Math.floor(hrs / 24)}d ago`;
}
import React, { useState } from "react";
import { View, Text, StyleSheet, Pressable, Image, Modal, Linking } from "react-native";
import { MapPin } from "lucide-react-native";
import { colors, fonts, eventTypeColor, timeAgo, Incident } from "../theme";

export default function IncidentCard({ incident }: { incident: Incident }) {
  const [expanded, setExpanded] = useState(false);
  const badgeColor = eventTypeColor[incident.eventType] ?? colors.breach;

  const mapUrl =
    incident.googleMapsUrl ||
    (incident.latitude != null && incident.longitude != null
      ? `https://maps.google.com/?q=${incident.latitude},${incident.longitude}`
      : null);

  const handleOpenMap = () => {
    if (mapUrl) {
      Linking.openURL(mapUrl).catch((err) =>
        console.error("Failed to open location link:", err)
      );
    }
  };

  return (
    <View style={styles.card}>
      <View style={styles.metaRow}>
        <Text style={[styles.type, { color: badgeColor }]}>
          {incident.eventType.replaceAll("_", " ")}
        </Text>
        <Text style={styles.time}>{timeAgo(incident.timestamp)}</Text>
      </View>

      {incident.photoBase64 && (
        <Pressable onPress={() => setExpanded(true)}>
          <Image
            source={{ uri: `data:image/jpeg;base64,${incident.photoBase64}` }}
            style={styles.photo}
            resizeMode="cover"
          />
        </Pressable>
      )}

      <View style={styles.footerRow}>
        <Text style={styles.device}>{incident.device}</Text>
        {mapUrl && (
          <Pressable style={styles.mapLink} onPress={handleOpenMap}>
            <MapPin size={13} color={colors.command} />
            <Text style={styles.mapLinkText}>View location</Text>
          </Pressable>
        )}
      </View>

      <Modal visible={expanded} transparent animationType="fade">
        <Pressable style={styles.lightbox} onPress={() => setExpanded(false)}>
          {incident.photoBase64 && (
            <Image
              source={{ uri: `data:image/jpeg;base64,${incident.photoBase64}` }}
              style={styles.lightboxPhoto}
              resizeMode="contain"
            />
          )}
        </Pressable>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: colors.cardSurface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    padding: 14,
    marginBottom: 12,
  },
  metaRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    marginBottom: 10,
  },
  type: {
    fontFamily: fonts.mono,
    fontSize: 11,
    fontWeight: "700",
    letterSpacing: 0.5,
  },
  time: {
    fontFamily: fonts.mono,
    fontSize: 11,
    color: colors.textMuted,
  },
  photo: {
    width: "100%",
    height: 200,
    borderRadius: 8,
    backgroundColor: colors.bgSlate,
  },
  footerRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    marginTop: 10,
  },
  device: {
    fontSize: 12,
    color: colors.textMuted,
  },
  mapLink: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
  },
  mapLinkText: {
    fontSize: 12,
    color: colors.command,
  },
  lightbox: {
    flex: 1,
    backgroundColor: "rgba(0,0,0,0.92)",
    justifyContent: "center",
    alignItems: "center",
    padding: 20,
  },
  lightboxPhoto: {
    width: "100%",
    height: "80%",
  },
});
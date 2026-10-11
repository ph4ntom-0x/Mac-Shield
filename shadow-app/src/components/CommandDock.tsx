import React, { useState } from "react";
import { View, Text, StyleSheet, Pressable, ActivityIndicator, Alert } from "react-native";
import { Camera, Siren } from "lucide-react-native";
import { collection, addDoc, serverTimestamp } from "firebase/firestore";
import { db } from "../firebase";
import { colors, fonts } from "../theme";

function dispatchCommand(action: string) {
  return addDoc(collection(db, "commands"), {
    action,
    status: "pending",
    createdAt: serverTimestamp(),
  });
}

export default function CommandDock() {
  const [pending, setPending] = useState<string | null>(null);

  async function handleDispatch(action: string) {
    setPending(action);
    try {
      await dispatchCommand(action);
    } catch (error: any) {
      Alert.alert("Command Failed", error.message || "Failed to dispatch command to Firestore.");
    } finally {
      setTimeout(() => setPending(null), 1200);
    }
  }

  return (
    <View style={styles.dock}>
      <Pressable
        style={styles.button}
        disabled={pending === "TRIGGER_ALARM"}
        onPress={() => handleDispatch("TRIGGER_ALARM")}
      >
        {pending === "TRIGGER_ALARM" ? (
          <ActivityIndicator color={colors.command} size="small" />
        ) : (
          <Siren size={16} color={colors.command} />
        )}
        <Text style={styles.buttonText}>Trigger alarm</Text>
      </Pressable>

      <Pressable
        style={styles.button}
        disabled={pending === "CAPTURE_PHOTO"}
        onPress={() => handleDispatch("CAPTURE_PHOTO")}
      >
        {pending === "CAPTURE_PHOTO" ? (
          <ActivityIndicator color={colors.command} size="small" />
        ) : (
          <Camera size={16} color={colors.command} />
        )}
        <Text style={styles.buttonText}>Capture photo</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  dock: {
    flexDirection: "row",
    gap: 10,
    marginBottom: 20,
  },
  button: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 8,
    paddingVertical: 12,
    backgroundColor: colors.cardSurface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 10,
  },
  buttonText: {
    fontFamily: fonts.mono,
    fontSize: 13,
    color: colors.textPrimary,
  },
});
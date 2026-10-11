import React, { useEffect, useState } from "react";
import {
  FlatList,
  View,
  Text,
  StyleSheet,
  StatusBar,
  Switch,
  ActivityIndicator,
} from "react-native";
import { SafeAreaProvider, SafeAreaView } from "react-native-safe-area-context";
import { ShieldAlert, Zap } from "lucide-react-native";
import {
  collection,
  doc,
  onSnapshot,
  orderBy,
  query,
  setDoc,
} from "firebase/firestore";
import { db } from "./src/firebase";
import { colors, fonts, Incident } from "./src/theme";
import StatusHeader from "./src/components/StatusHeader";
import CommandDock from "./src/components/CommandDock";
import IncidentCard from "./src/components/IncidentCard";

export default function App() {
  const [incidents, setIncidents] = useState<Incident[]>([]);
  const [isRealTime, setIsRealTime] = useState<boolean>(false);
  const [configLoading, setConfigLoading] = useState<boolean>(true);

  // 1. Listen for Incident Logs
  useEffect(() => {
    const q = query(collection(db, "incidents"), orderBy("timestamp", "desc"));
    const unsubscribe = onSnapshot(
      q,
      (snapshot) => {
        setIncidents(
          snapshot.docs.map((doc) => ({
            ...(doc.data() as Incident),
            incidentId: doc.data().incidentId || doc.id,
          }))
        );
      },
      (err) => console.error("[incidents listener]", err)
    );
    return unsubscribe;
  }, []);

  // 2. Listen for Real-Time Config Changes in Firestore
  useEffect(() => {
    const configRef = doc(db, "settings", "config");
    const unsubscribe = onSnapshot(
      configRef,
      (docSnap) => {
        if (docSnap.exists()) {
          const data = docSnap.data();
          setIsRealTime(!!data.realTimeMode);
        }
        setConfigLoading(false);
      },
      (err) => {
        console.error("[config listener]", err);
        setConfigLoading(false);
      }
    );
    return unsubscribe;
  }, []);

  // 3. Toggle Real-Time Mode in Firestore
  const toggleRealTime = async (newValue: boolean) => {
    setIsRealTime(newValue);
    try {
      const configRef = doc(db, "settings", "config");
      await setDoc(configRef, { realTimeMode: newValue }, { merge: true });
    } catch (err) {
      console.error("[toggleRealTime]", err);
      setIsRealTime(!newValue); // Rollback on failure
    }
  };

  return (
    <SafeAreaProvider>
      <SafeAreaView style={styles.safeArea}>
        <StatusBar backgroundColor={colors.bgDeep} barStyle="light-content" />
        <View style={styles.container}>
          <StatusHeader lastCheckIn={incidents[0]?.timestamp} />

          {/* Real-Time Security Toggle Card */}
          <View style={styles.toggleCard}>
            <View style={styles.toggleHeader}>
              <Zap
                size={18}
                color={isRealTime ? "#10B981" : colors.textMuted}
              />
              <Text style={styles.toggleTitle}>Real-Time Intruder Capture</Text>
            </View>
            <View style={styles.toggleRow}>
              <Text style={styles.toggleSubtitle}>
                {isRealTime
                  ? "Camera & Location capture on intrusion"
                  : "Alert-only logging mode"}
              </Text>
              {configLoading ? (
                <ActivityIndicator size="small" color="#10B981" />
              ) : (
                <Switch
                  value={isRealTime}
                  onValueChange={toggleRealTime}
                  trackColor={{ false: "#333333", true: "#10B981" }}
                  thumbColor={isRealTime ? "#FFFFFF" : "#888888"}
                />
              )}
            </View>
          </View>

          <CommandDock />

          {incidents.length === 0 ? (
            <View style={styles.emptyState}>
              <ShieldAlert color={colors.textMuted} size={28} />
              <Text style={styles.emptyTitle}>No incidents recorded yet.</Text>
              <Text style={styles.emptyHint}>
                This feed fills the moment ShadowAgent reports a failed login.
              </Text>
            </View>
          ) : (
            <FlatList
              data={incidents}
              keyExtractor={(item, index) =>
                item.incidentId || `incident-${index}`
              }
              renderItem={({ item }) => <IncidentCard incident={item} />}
              showsVerticalScrollIndicator={false}
            />
          )}
        </View>
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: colors.bgDeep,
  },
  container: {
    flex: 1,
    paddingHorizontal: 16,
    paddingTop: 12,
  },
  toggleCard: {
    backgroundColor: "#1E1E24",
    borderRadius: 12,
    padding: 14,
    marginVertical: 10,
    borderWidth: 1,
    borderColor: "#2A2A32",
  },
  toggleHeader: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    marginBottom: 4,
  },
  toggleTitle: {
    color: "#FFFFFF",
    fontSize: 14,
    fontWeight: "600",
    fontFamily: fonts.sans,
  },
  toggleRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  toggleSubtitle: {
    color: colors.textMuted,
    fontSize: 12,
    fontFamily: fonts.sans,
    flex: 1,
    marginRight: 10,
  },
  emptyState: {
    alignItems: "center",
    paddingTop: 80,
    gap: 6,
  },
  emptyTitle: {
    color: colors.textMuted,
    fontFamily: fonts.sans,
    fontSize: 14,
    marginTop: 8,
  },
  emptyHint: {
    color: colors.textMuted,
    fontFamily: fonts.sans,
    fontSize: 12,
    textAlign: "center",
    paddingHorizontal: 30,
  },
});
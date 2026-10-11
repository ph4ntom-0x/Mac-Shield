import React, { useEffect } from "react";
import { View, Text, StyleSheet } from "react-native";
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withRepeat,
  withTiming,
  Easing,
} from "react-native-reanimated";
import { colors, fonts, timeAgo } from "../theme";

export default function StatusHeader({ lastCheckIn }: { lastCheckIn?: string }) {
  const pulse = useSharedValue(0.4);

  useEffect(() => {
    pulse.value = withRepeat(
      withTiming(1, { duration: 1400, easing: Easing.inOut(Easing.ease) }),
      -1,
      true
    );
  }, []);

  const ringStyle = useAnimatedStyle(() => ({
    opacity: pulse.value,
    shadowOpacity: pulse.value * 0.7,
  }));

  return (
    <View style={styles.header}>
      <View style={styles.brand}>
        <Animated.View style={[styles.ring, ringStyle]} />
        <View>
          <Text style={styles.title}>SHADOW</Text>
          <Text style={styles.subtitle}>MacShield Control Center</Text>
        </View>
      </View>
      <View style={styles.status}>
        <View style={styles.dot} />
        <Text style={styles.statusText}>{timeAgo(lastCheckIn)}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    marginBottom: 24,
  },
  brand: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
  },
  ring: {
    width: 30,
    height: 30,
    borderRadius: 15,
    borderWidth: 3,
    borderColor: colors.online,
    shadowColor: colors.online,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 0 },
  },
  title: {
    fontFamily: fonts.mono,
    fontSize: 18,
    fontWeight: "700",
    color: colors.textPrimary,
    letterSpacing: 1,
  },
  subtitle: {
    fontSize: 11,
    color: colors.textMuted,
  },
  status: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
  },
  dot: {
    width: 7,
    height: 7,
    borderRadius: 4,
    backgroundColor: colors.online,
  },
  statusText: {
    fontFamily: fonts.mono,
    fontSize: 11,
    color: colors.textMuted,
  },
});

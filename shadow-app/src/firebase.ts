import { initializeApp } from "firebase/app";
import { getFirestore, connectFirestoreEmulator } from "firebase/firestore";

const firebaseConfig = {
  projectId: "mac-shield",
  apiKey: "AIzaSyD6Ac3TGRbGj2DbQ7wvrEhocO1xJo239WI",
};

export const app = initializeApp(firebaseConfig);
export const db = getFirestore(app);

const USE_EMULATOR = false;
const EMULATOR_HOST = "192.168.1.10";

if (USE_EMULATOR) {
  connectFirestoreEmulator(db, EMULATOR_HOST, 8080);
  console.log(`[firebase] connected to emulator at ${EMULATOR_HOST}:8080`);
}
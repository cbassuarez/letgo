import { motion } from "framer-motion";
import { usePermissionFlow } from "../hooks/usePermissionFlow";

interface PermissionGateProps {
  onDone: (permissions: { audio: boolean; motion: boolean; geolocation: boolean }) => void;
}

export const PermissionGate = ({ onDone }: PermissionGateProps): JSX.Element => {
  const { permissions, completed, enableAudio, enableGeo, enableMotion } = usePermissionFlow();

  return (
    <section className="mx-auto w-full max-w-xl rounded-3xl border border-fog/20 bg-ink/70 p-6 shadow-panel backdrop-blur">
      <h2 className="font-display text-2xl">Join The Conductor Field</h2>
      <p className="mt-3 text-sm text-fog/80">
        This phone becomes a unique participant. Enable audio, motion, and location so your device can carry a live branch of the film.
      </p>

      <div className="mt-6 grid gap-3">
        <button className="rounded-xl bg-ember px-4 py-3 text-left text-sm font-semibold text-fog" onClick={() => void enableAudio()}>
          {permissions.audio ? "Audio Ready" : "Enable Audio"}
        </button>
        <button className="rounded-xl bg-leaf px-4 py-3 text-left text-sm font-semibold text-fog" onClick={() => void enableMotion()}>
          {permissions.motion ? "Motion Ready" : "Enable Motion"}
        </button>
        <button className="rounded-xl bg-fog px-4 py-3 text-left text-sm font-semibold text-ink" onClick={() => void enableGeo()}>
          {permissions.geolocation ? "Location Ready" : "Enable Location"}
        </button>
      </div>

      {completed ? (
        <motion.button
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          className="mt-6 w-full rounded-xl border border-fog/40 bg-transparent px-4 py-3 font-semibold"
          onClick={() => onDone(permissions)}
        >
          Continue To Film
        </motion.button>
      ) : null}
    </section>
  );
};

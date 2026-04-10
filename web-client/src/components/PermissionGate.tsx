import { motion } from "framer-motion";
import { usePermissionFlow } from "../hooks/usePermissionFlow";

interface PermissionGateProps {
  onDone: (permissions: { audio: boolean; motion: boolean; geolocation: boolean }) => void;
}

export const PermissionGate = ({ onDone }: PermissionGateProps): JSX.Element => {
  const { permissions, completed, enableAudio, enableGeo, enableMotion } = usePermissionFlow();

  return (
    <section className="cyanotype-panel mx-auto mt-8 w-full max-w-xl p-6">
      <p className="cyanotype-kicker">ACCESS PROTOCOL</p>
      <h2 className="mt-3 font-display text-3xl">Join The Conductor Field</h2>
      <p className="mt-3 text-sm text-cyanotype-100/80">
        This phone becomes a unique participant. Enable audio and motion to join live control.
        Location is optional and only improves spatial grouping.
      </p>

      <div className="mt-6 grid gap-3">
        <button className="cyanotype-cta text-left" onClick={() => void enableAudio()}>
          {permissions.audio ? "Audio Ready" : "Enable Audio"}
        </button>
        <button className="cyanotype-cta text-left" onClick={() => void enableMotion()}>
          {permissions.motion ? "Motion Ready" : "Enable Motion"}
        </button>
        <button className="cyanotype-cta text-left" onClick={() => void enableGeo()}>
          {permissions.geolocation ? "Location Ready" : "Enable Location (Optional)"}
        </button>
      </div>

      {completed ? (
        <motion.button
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          className="cyanotype-cta mt-6 w-full justify-center"
          onClick={() => onDone(permissions)}
        >
          Continue To Film
        </motion.button>
      ) : null}
    </section>
  );
};

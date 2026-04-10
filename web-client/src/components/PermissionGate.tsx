import { motion } from "framer-motion";
import { usePermissionFlow } from "../hooks/usePermissionFlow";

interface PermissionGateProps {
  onDone: (permissions: { audio: boolean; motion: boolean; geolocation: boolean }) => void;
}

export const PermissionGate = ({ onDone }: PermissionGateProps): JSX.Element => {
  const { permissions, completed, enableAudio, enableGeo, enableMotion } = usePermissionFlow();

  return (
    <section className="mx-auto mt-10 w-full max-w-4xl border-t border-cyanotype-200/30 py-8">
      <p className="cyanotype-kicker">ACCESS PROTOCOL</p>
      <h2 className="mt-3 text-4xl font-semibold leading-[0.95] sm:text-6xl">Join The Conductor Field</h2>
      <p className="font-display mt-6 text-2xl text-cyanotype-000/88 sm:text-4xl">
        Activate your device as an expressive instrument.
      </p>
      <p className="mt-4 max-w-3xl text-sm text-cyanotype-100/80 sm:text-base">
        This phone becomes a unique participant. Enable audio and motion to join live control.
        Location is optional and only improves spatial grouping.
      </p>

      <div className="mt-8 grid gap-4 border-t border-cyanotype-200/25 pt-5">
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
          className="cyanotype-cta mt-8 w-fit"
          onClick={() => onDone(permissions)}
        >
          Continue To Film
        </motion.button>
      ) : null}
    </section>
  );
};

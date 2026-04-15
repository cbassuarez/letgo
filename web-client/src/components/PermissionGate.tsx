import { motion } from "framer-motion";
import { usePermissionFlow } from "../hooks/usePermissionFlow";

interface PermissionGateProps {
  onDone: (permissions: { audio: boolean; motion: boolean; geolocation: boolean }) => void;
}

export const PermissionGate = ({ onDone }: PermissionGateProps): JSX.Element => {
  const { permissions, completed, enableAudio, enableGeo, enableMotion } = usePermissionFlow();

  return (
    <motion.section
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.26 }}
      role="dialog"
      aria-modal="true"
      aria-label="Live access permissions"
      className="live-permission-modal"
    >
      <p className="live-ribbon-label">ACCESS</p>
      <h2 className="live-permission-title">Enable Device Permissions</h2>
      <p className="live-permission-copy">
        Audio and motion are required. Location is optional.
      </p>

      <div className="live-permission-grid">
        <button
          className={`live-permission-button ${permissions.audio ? "ready" : ""}`}
          onClick={() => void enableAudio()}
        >
          {permissions.audio ? "Audio Ready" : "Enable Audio"}
        </button>
        <button
          className={`live-permission-button ${permissions.motion ? "ready" : ""}`}
          onClick={() => void enableMotion()}
        >
          {permissions.motion ? "Motion Ready" : "Enable Motion"}
        </button>
        <button
          className={`live-permission-button ${permissions.geolocation ? "ready" : ""}`}
          onClick={() => void enableGeo()}
        >
          {permissions.geolocation ? "Location Ready" : "Enable Location (Optional)"}
        </button>
      </div>

      {completed ? (
        <motion.button
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          className="live-permission-continue"
          onClick={() => onDone(permissions)}
        >
          Continue
        </motion.button>
      ) : null}
    </motion.section>
  );
};

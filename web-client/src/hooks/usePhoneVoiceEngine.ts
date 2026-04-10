import type { PhoneAudioAckPayload, PhoneAudioCommandPayload } from "@conductor/protocol";
import { useCallback, useEffect, useRef } from "react";

interface UsePhoneVoiceEngineInput {
  enabled: boolean;
  hashedId: string;
  onAck: (payload: PhoneAudioAckPayload) => void;
}

export const usePhoneVoiceEngine = ({ enabled, hashedId, onAck }: UsePhoneVoiceEngineInput) => {
  const contextRef = useRef<AudioContext | null>(null);
  const noteVoicesRef = useRef<Map<number, { oscillator: OscillatorNode; gain: GainNode }>>(new Map());
  const ambientRef = useRef<{ source: AudioBufferSourceNode; gain: GainNode } | null>(null);

  useEffect(() => {
    return () => {
      const context = contextRef.current;
      if (context) {
        void context.close();
      }
      contextRef.current = null;
      noteVoicesRef.current.clear();
      ambientRef.current = null;
    };
  }, []);

  const ensureContext = useCallback(async (): Promise<AudioContext> => {
    if (!contextRef.current) {
      contextRef.current = new AudioContext();
    }
    if (contextRef.current.state !== "running") {
      await contextRef.current.resume();
    }
    return contextRef.current;
  }, []);

  const stopAll = useCallback(() => {
    for (const [, voice] of noteVoicesRef.current.entries()) {
      voice.oscillator.stop();
    }
    noteVoicesRef.current.clear();

    if (ambientRef.current) {
      ambientRef.current.source.stop();
      ambientRef.current = null;
    }
  }, []);

  const handleCommand = useCallback(
    async (command: PhoneAudioCommandPayload | null) => {
      if (!enabled || !command) {
        return;
      }
      if (!command.targetHashedIds.includes(hashedId)) {
        return;
      }

      try {
        const context = await ensureContext();

        switch (command.kind) {
          case "note_on": {
            const note = typeof command.note === "number" ? command.note : 60;
            if (noteVoicesRef.current.has(note)) {
              break;
            }
            const frequency = 440 * Math.pow(2, (note - 69) / 12);
            const oscillator = context.createOscillator();
            oscillator.type = "sine";
            oscillator.frequency.value = frequency;
            const gain = context.createGain();
            gain.gain.value = (command.velocity ?? 0.75) * (command.gain ?? 0.35);
            oscillator.connect(gain).connect(context.destination);
            oscillator.start();
            noteVoicesRef.current.set(note, { oscillator, gain });
            break;
          }
          case "note_off": {
            const note = typeof command.note === "number" ? command.note : undefined;
            if (typeof note === "number") {
              const voice = noteVoicesRef.current.get(note);
              if (voice) {
                voice.oscillator.stop();
                noteVoicesRef.current.delete(note);
              }
            } else {
              stopAll();
            }
            break;
          }
          case "sample_trigger": {
            const oscillator = context.createOscillator();
            oscillator.type = "triangle";
            oscillator.frequency.value = 180 + Math.random() * 220;
            const gain = context.createGain();
            gain.gain.value = command.gain ?? 0.22;
            oscillator.connect(gain).connect(context.destination);
            oscillator.start();
            oscillator.stop(context.currentTime + 0.18);
            break;
          }
          case "ambient_noise": {
            if (ambientRef.current) {
              ambientRef.current.source.stop();
              ambientRef.current = null;
            }

            const duration = 1.5;
            const sampleRate = context.sampleRate;
            const frameCount = Math.floor(sampleRate * duration);
            const buffer = context.createBuffer(1, frameCount, sampleRate);
            const channel = buffer.getChannelData(0);
            for (let i = 0; i < frameCount; i += 1) {
              channel[i] = Math.random() * 2 - 1;
            }

            const source = context.createBufferSource();
            source.buffer = buffer;
            source.loop = true;
            const gain = context.createGain();
            gain.gain.value = command.gain ?? 0.06;
            source.connect(gain).connect(context.destination);
            source.start();
            ambientRef.current = { source, gain };
            break;
          }
          case "stop_all": {
            stopAll();
            break;
          }
        }

        onAck({
          commandId: command.commandId,
          hashedId,
          ok: true,
          receivedAt: Date.now()
        });
      } catch (error) {
        onAck({
          commandId: command.commandId,
          hashedId,
          ok: false,
          detail: error instanceof Error ? error.message : "phone_audio_error",
          receivedAt: Date.now()
        });
      }
    },
    [enabled, ensureContext, hashedId, onAck, stopAll]
  );

  return {
    handleCommand
  };
};

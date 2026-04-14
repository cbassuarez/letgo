import type { PhoneAudioAckPayload, PhoneAudioCommandPayload } from "@conductor/protocol";
import { useCallback, useEffect, useRef } from "react";

interface UsePhoneVoiceEngineInput {
  enabled: boolean;
  hashedId: string;
  onAck: (payload: PhoneAudioAckPayload) => void;
}

export const usePhoneVoiceEngine = ({ enabled, hashedId, onAck }: UsePhoneVoiceEngineInput) => {
  const contextRef = useRef<AudioContext | null>(null);
  const noteVoicesRef = useRef<Map<number, { oscillator: OscillatorNode; gain: GainNode; pan: StereoPannerNode }>>(new Map());
  const ambientRef = useRef<{ source: AudioBufferSourceNode; gain: GainNode } | null>(null);
  const sampleBuffersRef = useRef<Map<string, AudioBuffer>>(new Map());
  const preloadStateRef = useRef<"idle" | "loading" | "ready" | "partial">("idle");

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

  const pickRenderHints = useCallback(
    (command: PhoneAudioCommandPayload) => {
      return command.renderHintsByTarget?.[hashedId] ?? command.renderHints;
    },
    [hashedId]
  );

  const sampleCandidatesForID = useCallback((sampleID: string): string[] => {
    const compact = sampleID.trim();
    if (!compact) {
      return [];
    }
    const variants = new Set<string>([
      `/assets/choir/${compact}.wav`,
      `/assets/choir/${compact}.mp3`,
      `/audio/choir/${compact}.wav`,
      `/audio/choir/${compact}.mp3`
    ]);
    return [...variants];
  }, []);

  const loadSampleBuffer = useCallback(
    async (context: AudioContext, sampleID: string): Promise<AudioBuffer | null> => {
      if (sampleBuffersRef.current.has(sampleID)) {
        return sampleBuffersRef.current.get(sampleID) ?? null;
      }
      const urls = sampleCandidatesForID(sampleID);
      for (const url of urls) {
        try {
          const response = await fetch(url, { cache: "force-cache" });
          if (!response.ok) {
            continue;
          }
          const arrayBuffer = await response.arrayBuffer();
          const decoded = await context.decodeAudioData(arrayBuffer.slice(0));
          sampleBuffersRef.current.set(sampleID, decoded);
          return decoded;
        } catch {
          continue;
        }
      }
      return null;
    },
    [sampleCandidatesForID]
  );

  const preloadChoirBanks = useCallback(async (): Promise<void> => {
    if (!enabled || preloadStateRef.current === "loading" || preloadStateRef.current === "ready") {
      return;
    }
    preloadStateRef.current = "loading";
    try {
      const context = await ensureContext();
      const canonical = [
        "choir-bank1-pad",
        "choir-bank1-texture",
        "choir-bank1-pulse",
        "choir-bank2-pad",
        "choir-bank2-texture",
        "choir-bank2-pulse",
        "choir-bank3-pad",
        "choir-bank3-texture",
        "choir-bank3-pulse"
      ];
      const loaded = await Promise.all(canonical.map((id) => loadSampleBuffer(context, id)));
      const readyCount = loaded.filter((entry) => entry !== null).length;
      preloadStateRef.current = readyCount === canonical.length ? "ready" : (readyCount > 0 ? "partial" : "idle");
    } catch {
      preloadStateRef.current = "idle";
    }
  }, [enabled, ensureContext, loadSampleBuffer]);

  useEffect(() => {
    void preloadChoirBanks();
  }, [preloadChoirBanks]);

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
        const hints = pickRenderHints(command);
        const panValue = Math.max(-1, Math.min(1, hints?.pan ?? 0));
        const detuneCents = Math.max(-1200, Math.min(1200, hints?.detuneCents ?? 0));
        const grainMix = Math.max(0, Math.min(1, hints?.grainMix ?? 0.35));
        let renderMode = "osc";

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
            oscillator.detune.value = detuneCents;
            const gain = context.createGain();
            gain.gain.value = (command.velocity ?? 0.75) * (command.gain ?? 0.35);
            const pan = context.createStereoPanner();
            pan.pan.value = panValue;
            oscillator.connect(gain).connect(pan).connect(context.destination);
            oscillator.start();
            noteVoicesRef.current.set(note, { oscillator, gain, pan });
            renderMode = "osc-note";
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
            const candidates = [
              command.sampleId ?? "",
              `choir-bank${Math.max(1, Math.min(3, typeof command.note === "number" ? Math.floor(command.note / 12) : 1))}-texture`,
              `choir-bank${Math.max(1, Math.min(3, typeof command.note === "number" ? Math.floor(command.note / 12) : 1))}-pulse`
            ].filter(Boolean);

            let rendered = false;
            for (const candidate of candidates) {
              const buffer = await loadSampleBuffer(context, candidate);
              if (!buffer) {
                continue;
              }
              const source = context.createBufferSource();
              source.buffer = buffer;
              source.detune.value = detuneCents;
              const gain = context.createGain();
              gain.gain.value = (command.gain ?? 0.22) * (0.7 + grainMix * 0.3);
              const pan = context.createStereoPanner();
              pan.pan.value = panValue;
              source.connect(gain).connect(pan).connect(context.destination);
              source.start();
              rendered = true;
              renderMode = `sample:${candidate}`;
              break;
            }

            if (!rendered) {
              const oscillator = context.createOscillator();
              oscillator.type = "triangle";
              oscillator.frequency.value = 180 + Math.random() * 220;
              oscillator.detune.value = detuneCents;
              const gain = context.createGain();
              gain.gain.value = command.gain ?? 0.22;
              const pan = context.createStereoPanner();
              pan.pan.value = panValue;
              oscillator.connect(gain).connect(pan).connect(context.destination);
              oscillator.start();
              oscillator.stop(context.currentTime + (0.14 + grainMix * 0.1));
              renderMode = "osc-fallback";
            }
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
            const pan = context.createStereoPanner();
            pan.pan.value = panValue;
            source.connect(gain).connect(pan).connect(context.destination);
            source.start();
            ambientRef.current = { source, gain };
            renderMode = "ambient";
            break;
          }
          case "stop_all": {
            stopAll();
            renderMode = "stop_all";
            break;
          }
        }

        onAck({
          commandId: command.commandId,
          hashedId,
          ok: true,
          detail: `mode=${renderMode};preload=${preloadStateRef.current}`,
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

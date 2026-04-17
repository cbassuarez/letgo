import type {
  GroupStemStartPayload,
  GroupStemStopPayload,
  PhoneAudioAckPayload,
  PhoneAudioCommandPayload,
  VoiceStreamDescriptor,
  VoiceStreamStartPayload,
  VoiceStreamStopPayload
} from "@conductor/protocol";
import { useCallback, useEffect, useRef } from "react";

interface UsePhoneVoiceEngineInput {
  enabled: boolean;
  hashedId: string;
  onAck: (payload: PhoneAudioAckPayload) => void;
}

type VoiceEntry = {
  element: HTMLAudioElement;
  descriptor: VoiceStreamDescriptor;
  note?: number;
};

const isLocalSynthFallbackEnabled = (): boolean => {
  const raw = import.meta.env.VITE_PHONE_AUDIO_LOCAL_SYNTH_ENABLE;
  if (typeof raw !== "string") {
    return false;
  }
  const normalized = raw.trim().toLowerCase();
  return normalized === "1" || normalized === "true" || normalized === "yes";
};

export const usePhoneVoiceEngine = ({ enabled, hashedId, onAck }: UsePhoneVoiceEngineInput) => {
  const localSynthFallbackEnabledRef = useRef<boolean>(isLocalSynthFallbackEnabled());
  const contextRef = useRef<AudioContext | null>(null);
  const noteVoicesRef = useRef<Map<number, { oscillator: OscillatorNode; gain: GainNode; pan: StereoPannerNode }>>(new Map());
  const ambientRef = useRef<{ source: AudioBufferSourceNode; gain: GainNode } | null>(null);
  const sampleBuffersRef = useRef<Map<string, AudioBuffer>>(new Map());
  const preloadStateRef = useRef<"idle" | "loading" | "ready" | "partial">("idle");
  const voiceStreamsByVoiceIdRef = useRef<Map<string, VoiceEntry>>(new Map());
  const voiceIdByTrackIdRef = useRef<Map<string, string>>(new Map());
  const voiceIdByNoteRef = useRef<Map<number, string>>(new Map());
  const activeGroupStreamsRef = useRef<Map<string, HTMLAudioElement>>(new Map());

  useEffect(() => {
    return () => {
      const context = contextRef.current;
      if (context) {
        void context.close();
      }
      contextRef.current = null;
      noteVoicesRef.current.clear();
      ambientRef.current = null;
      for (const [, entry] of voiceStreamsByVoiceIdRef.current.entries()) {
        entry.element.pause();
        entry.element.src = "";
      }
      voiceStreamsByVoiceIdRef.current.clear();
      voiceIdByTrackIdRef.current.clear();
      voiceIdByNoteRef.current.clear();
      for (const [, element] of activeGroupStreamsRef.current.entries()) {
        element.pause();
        element.src = "";
      }
      activeGroupStreamsRef.current.clear();
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
      preloadStateRef.current = readyCount === canonical.length ? "ready" : readyCount > 0 ? "partial" : "idle";
    } catch {
      preloadStateRef.current = "idle";
    }
  }, [enabled, ensureContext, loadSampleBuffer]);

  useEffect(() => {
    void preloadChoirBanks();
  }, [preloadChoirBanks]);

  const stopLocalSynth = useCallback(() => {
    for (const [, voice] of noteVoicesRef.current.entries()) {
      voice.oscillator.stop();
    }
    noteVoicesRef.current.clear();

    if (ambientRef.current) {
      ambientRef.current.source.stop();
      ambientRef.current = null;
    }
  }, []);

  const stopAllVoiceStreams = useCallback(() => {
    for (const [, voice] of voiceStreamsByVoiceIdRef.current.entries()) {
      voice.element.pause();
      voice.element.src = "";
    }
    voiceStreamsByVoiceIdRef.current.clear();
    voiceIdByTrackIdRef.current.clear();
    voiceIdByNoteRef.current.clear();
  }, []);

  const stopAllGroupStreams = useCallback(() => {
    for (const [, element] of activeGroupStreamsRef.current.entries()) {
      element.pause();
      element.src = "";
    }
    activeGroupStreamsRef.current.clear();
  }, []);

  const startVoiceStream = useCallback(
    async (
      descriptor: VoiceStreamDescriptor,
      commandId: string,
      options?: {
        note?: number;
      }
    ): Promise<"started" | "already_started" | "failed"> => {
      if (!descriptor.streamUrl || descriptor.streamUrl.trim().length === 0) {
        onAck({
          commandId,
          hashedId,
          ok: false,
          detail: "stream_missing_url",
          streamStatus: "track_lost",
          streamReason: "missing_stream_url",
          voiceId: descriptor.voiceId,
          trackId: descriptor.trackId,
          receivedAt: Date.now()
        });
        return "failed";
      }

      const existing = voiceStreamsByVoiceIdRef.current.get(descriptor.voiceId);
      if (existing && existing.descriptor.trackId === descriptor.trackId) {
        return "already_started";
      }

      if (existing) {
        existing.element.pause();
        existing.element.src = "";
        voiceStreamsByVoiceIdRef.current.delete(descriptor.voiceId);
      }

      const element = new Audio();
      element.preload = "auto";
      element.autoplay = true;
      element.loop = true;
      element.crossOrigin = "anonymous";
      element.setAttribute("playsinline", "true");
      element.src = descriptor.streamUrl;

      element.addEventListener("stalled", () => {
        onAck({
          commandId,
          hashedId,
          ok: false,
          detail: "stream_stalled",
          streamStatus: "underrun",
          streamReason: "stalled",
          voiceId: descriptor.voiceId,
          trackId: descriptor.trackId,
          receivedAt: Date.now()
        });
      });

      element.addEventListener("error", () => {
        onAck({
          commandId,
          hashedId,
          ok: false,
          detail: "stream_error",
          streamStatus: "track_lost",
          streamReason: "audio_element_error",
          voiceId: descriptor.voiceId,
          trackId: descriptor.trackId,
          receivedAt: Date.now()
        });
      });

      try {
        await element.play();
        voiceStreamsByVoiceIdRef.current.set(descriptor.voiceId, {
          element,
          descriptor,
          note: options?.note
        });
        voiceIdByTrackIdRef.current.set(descriptor.trackId, descriptor.voiceId);
        if (typeof options?.note === "number") {
          voiceIdByNoteRef.current.set(options.note, descriptor.voiceId);
        }
        onAck({
          commandId,
          hashedId,
          ok: true,
          detail: "stream_started",
          streamStatus: "subscribed",
          voiceId: descriptor.voiceId,
          trackId: descriptor.trackId,
          receivedAt: Date.now()
        });
        return "started";
      } catch (error) {
        onAck({
          commandId,
          hashedId,
          ok: false,
          detail: error instanceof Error ? error.message : "stream_play_failed",
          streamStatus: "track_lost",
          streamReason: "play_failed",
          voiceId: descriptor.voiceId,
          trackId: descriptor.trackId,
          receivedAt: Date.now()
        });
        return "failed";
      }
    },
    [hashedId, onAck]
  );

  const stopVoiceStream = useCallback(
    (payload: { commandId: string; voiceId?: string; trackId?: string; reason?: string; note?: number }) => {
      let voiceId: string | undefined = payload.voiceId;

      if (!voiceId && payload.trackId) {
        voiceId = voiceIdByTrackIdRef.current.get(payload.trackId);
      }

      if (!voiceId && typeof payload.note === "number") {
        voiceId = voiceIdByNoteRef.current.get(payload.note);
      }

      if (!voiceId) {
        return;
      }

      const entry = voiceStreamsByVoiceIdRef.current.get(voiceId);
      if (!entry) {
        return;
      }

      entry.element.pause();
      entry.element.src = "";
      voiceStreamsByVoiceIdRef.current.delete(voiceId);
      voiceIdByTrackIdRef.current.delete(entry.descriptor.trackId);
      if (typeof entry.note === "number") {
        voiceIdByNoteRef.current.delete(entry.note);
      }

      onAck({
        commandId: payload.commandId,
        hashedId,
        ok: true,
        detail: `stream_stopped:${payload.reason ?? "manual"}`,
        streamStatus: "fallback_group",
        streamReason: payload.reason,
        voiceId,
        trackId: entry.descriptor.trackId,
        receivedAt: Date.now()
      });
    },
    [hashedId, onAck]
  );

  const startGroupStem = useCallback(
    async (payload: GroupStemStartPayload): Promise<void> => {
      if (!payload.hashedIds.includes(hashedId)) {
        return;
      }

      const descriptor = payload.group;
      if (!descriptor.streamUrl || descriptor.streamUrl.trim().length === 0) {
        onAck({
          commandId: payload.commandId,
          hashedId,
          ok: false,
          detail: "group_stream_missing_url",
          streamStatus: "track_lost",
          streamReason: "group_missing_stream_url",
          receivedAt: Date.now()
        });
        return;
      }

      const existing = activeGroupStreamsRef.current.get(descriptor.groupId);
      if (existing) {
        return;
      }

      const element = new Audio();
      element.preload = "auto";
      element.autoplay = true;
      element.loop = true;
      element.crossOrigin = "anonymous";
      element.setAttribute("playsinline", "true");
      element.src = descriptor.streamUrl;

      try {
        await element.play();
        activeGroupStreamsRef.current.set(descriptor.groupId, element);
        onAck({
          commandId: payload.commandId,
          hashedId,
          ok: true,
          detail: "group_stream_started",
          streamStatus: "fallback_group",
          streamReason: payload.reason,
          receivedAt: Date.now()
        });
      } catch (error) {
        onAck({
          commandId: payload.commandId,
          hashedId,
          ok: false,
          detail: error instanceof Error ? error.message : "group_stream_play_failed",
          streamStatus: "track_lost",
          streamReason: "group_play_failed",
          receivedAt: Date.now()
        });
      }
    },
    [hashedId, onAck]
  );

  const stopGroupStem = useCallback(
    (payload: GroupStemStopPayload): void => {
      if (!payload.hashedIds.includes(hashedId)) {
        return;
      }
      const element = activeGroupStreamsRef.current.get(payload.groupId);
      if (!element) {
        return;
      }
      element.pause();
      element.src = "";
      activeGroupStreamsRef.current.delete(payload.groupId);
      onAck({
        commandId: payload.commandId,
        hashedId,
        ok: true,
        detail: `group_stream_stopped:${payload.reason ?? "manual"}`,
        streamStatus: "fallback_group",
        streamReason: payload.reason,
        receivedAt: Date.now()
      });
    },
    [hashedId, onAck]
  );

  const renderLocalCommand = useCallback(
    async (command: PhoneAudioCommandPayload): Promise<string> => {
      const context = await ensureContext();
      const hints = pickRenderHints(command);
      const panValue = Math.max(-1, Math.min(1, hints?.pan ?? 0));
      const detuneCents = Math.max(-1200, Math.min(1200, hints?.detuneCents ?? 0));
      const grainMix = Math.max(0, Math.min(1, hints?.grainMix ?? 0.35));

      switch (command.kind) {
        case "note_on": {
          const note = typeof command.note === "number" ? command.note : 60;
          if (noteVoicesRef.current.has(note)) {
            return "osc-note";
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
          return "osc-note";
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
            stopLocalSynth();
          }
          return "osc-note-off";
        }
        case "sample_trigger": {
          const candidates = [
            command.sampleId ?? "",
            `choir-bank${Math.max(1, Math.min(3, typeof command.note === "number" ? Math.floor(command.note / 12) : 1))}-texture`,
            `choir-bank${Math.max(1, Math.min(3, typeof command.note === "number" ? Math.floor(command.note / 12) : 1))}-pulse`
          ].filter(Boolean);

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
            return `sample:${candidate}`;
          }

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
          return "osc-fallback";
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
          return "ambient";
        }
        case "stop_all": {
          stopLocalSynth();
          stopAllVoiceStreams();
          stopAllGroupStreams();
          return "stop_all";
        }
      }
    },
    [ensureContext, hashedId, loadSampleBuffer, onAck, pickRenderHints, stopAllGroupStreams, stopAllVoiceStreams, stopLocalSynth]
  );

  const handleCommand = useCallback(
    async (command: PhoneAudioCommandPayload | null) => {
      if (!enabled || !command) {
        return;
      }
      if (!command.targetHashedIds.includes(hashedId)) {
        return;
      }

      try {
        const streamDescriptor = command.streamByTarget?.[hashedId] ?? command.stream;

        if (command.kind === "note_off") {
          stopVoiceStream({
            commandId: command.commandId,
            note: command.note,
            reason: "note_off"
          });
          if (localSynthFallbackEnabledRef.current) {
            await renderLocalCommand(command);
          }
          return;
        }

        if (command.kind === "stop_all") {
          stopAllVoiceStreams();
          stopAllGroupStreams();
          stopLocalSynth();
          onAck({
            commandId: command.commandId,
            hashedId,
            ok: true,
            detail: "stop_all",
            streamStatus: "fallback_group",
            streamReason: "show_stop",
            receivedAt: Date.now()
          });
          return;
        }

        if (streamDescriptor) {
          const startState = await startVoiceStream(streamDescriptor, command.commandId, {
            note: command.note
          });
          if (startState !== "failed") {
            return;
          }
        }

        if (!localSynthFallbackEnabledRef.current) {
          onAck({
            commandId: command.commandId,
            hashedId,
            ok: false,
            detail: "local_synth_disabled",
            streamStatus: "track_lost",
            streamReason: "external_stream_required",
            receivedAt: Date.now()
          });
          return;
        }

        const renderMode = await renderLocalCommand(command);
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
    [
      enabled,
      hashedId,
      onAck,
      renderLocalCommand,
      startVoiceStream,
      stopAllGroupStreams,
      stopAllVoiceStreams,
      stopLocalSynth,
      stopVoiceStream
    ]
  );

  const handleVoiceStreamStart = useCallback(
    async (payload: VoiceStreamStartPayload | null) => {
      if (!enabled || !payload || payload.hashedId !== hashedId) {
        return;
      }
      await startVoiceStream(payload.stream, payload.commandId, { note: payload.note });
    },
    [enabled, hashedId, startVoiceStream]
  );

  const handleVoiceStreamStop = useCallback(
    (payload: VoiceStreamStopPayload | null) => {
      if (!enabled || !payload || payload.hashedId !== hashedId) {
        return;
      }
      stopVoiceStream({
        commandId: payload.commandId,
        voiceId: payload.voiceId,
        trackId: payload.trackId,
        note: payload.note,
        reason: payload.reason
      });
    },
    [enabled, hashedId, stopVoiceStream]
  );

  const handleGroupStemStart = useCallback(
    async (payload: GroupStemStartPayload | null) => {
      if (!enabled || !payload) {
        return;
      }
      await startGroupStem(payload);
    },
    [enabled, startGroupStem]
  );

  const handleGroupStemStop = useCallback(
    (payload: GroupStemStopPayload | null) => {
      if (!enabled || !payload) {
        return;
      }
      stopGroupStem(payload);
    },
    [enabled, stopGroupStem]
  );

  return {
    handleCommand,
    handleVoiceStreamStart,
    handleVoiceStreamStop,
    handleGroupStemStart,
    handleGroupStemStop
  };
};

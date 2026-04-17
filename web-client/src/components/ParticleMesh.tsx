import { useEffect, useRef } from "react";

export interface ParticleMeshProps {
  phrases: string[];
  phraseDurationMs?: number;
  pressure?: number;
  density?: number;
  reducedMotion?: boolean;
  fontFamily?: string;
  className?: string;
}

const VERT_SHADER = `
  attribute vec2 a_pos;
  attribute float a_life;
  uniform vec2 u_resolution;
  uniform float u_size;
  varying float v_life;
  void main() {
    vec2 zeroToOne = a_pos / u_resolution;
    vec2 clip = zeroToOne * 2.0 - 1.0;
    gl_Position = vec4(clip.x, -clip.y, 0.0, 1.0);
    gl_PointSize = u_size;
    v_life = a_life;
  }
`;

const FRAG_SHADER = `
  precision mediump float;
  uniform vec3 u_color;
  varying float v_life;
  void main() {
    vec2 c = gl_PointCoord - vec2(0.5);
    float d = length(c);
    if (d > 0.5) discard;
    float edge = 1.0 - smoothstep(0.18, 0.5, d);
    gl_FragColor = vec4(u_color, edge * v_life);
  }
`;

const compileShader = (gl: WebGLRenderingContext, type: number, source: string): WebGLShader | null => {
  const shader = gl.createShader(type);
  if (!shader) return null;
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    gl.deleteShader(shader);
    return null;
  }
  return shader;
};

const linkProgram = (gl: WebGLRenderingContext): WebGLProgram | null => {
  const vs = compileShader(gl, gl.VERTEX_SHADER, VERT_SHADER);
  const fs = compileShader(gl, gl.FRAGMENT_SHADER, FRAG_SHADER);
  if (!vs || !fs) return null;
  const program = gl.createProgram();
  if (!program) return null;
  gl.attachShader(program, vs);
  gl.attachShader(program, fs);
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    gl.deleteProgram(program);
    return null;
  }
  return program;
};

const resolveParticleCount = (density: number): number => {
  const cores = typeof navigator !== "undefined" ? navigator.hardwareConcurrency || 4 : 4;
  const base = cores >= 8 ? 12000 : cores >= 4 ? 8000 : 5000;
  return Math.max(1200, Math.floor(base * Math.max(0.2, Math.min(1.5, density))));
};

const samplePhrasePositions = (
  text: string,
  width: number,
  height: number,
  fontFamily: string,
  targetCount: number
): Float32Array => {
  const out = new Float32Array(targetCount * 2);
  if (!text || width <= 0 || height <= 0) {
    for (let i = 0; i < targetCount; i++) {
      out[i * 2] = Math.random() * width;
      out[i * 2 + 1] = Math.random() * height;
    }
    return out;
  }
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d");
  if (!ctx) return out;

  // Fit text to ~82% of the narrower dimension.
  const maxWidth = width * 0.86;
  const maxHeight = height * 0.48;
  let fontSize = Math.min(maxHeight, width * 0.18);
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.font = `600 ${fontSize}px "${fontFamily}", sans-serif`;
  while (ctx.measureText(text).width > maxWidth && fontSize > 18) {
    fontSize = Math.max(18, fontSize - 4);
    ctx.font = `600 ${fontSize}px "${fontFamily}", sans-serif`;
  }

  ctx.clearRect(0, 0, width, height);
  ctx.fillStyle = "#ffffff";
  ctx.fillText(text, width / 2, height / 2);

  const data = ctx.getImageData(0, 0, width, height).data;
  const hits: number[] = [];
  const stride = Math.max(2, Math.round(Math.min(width, height) / 520));
  for (let y = 0; y < height; y += stride) {
    const rowOffset = y * width * 4;
    for (let x = 0; x < width; x += stride) {
      if (data[rowOffset + x * 4 + 3] > 140) {
        hits.push(x, y);
      }
    }
  }

  const pairs = hits.length / 2;
  if (pairs === 0) {
    for (let i = 0; i < targetCount; i++) {
      out[i * 2] = Math.random() * width;
      out[i * 2 + 1] = Math.random() * height;
    }
    return out;
  }

  for (let i = 0; i < targetCount; i++) {
    const src = Math.floor(Math.random() * pairs);
    out[i * 2] = hits[src * 2] + (Math.random() - 0.5) * stride;
    out[i * 2 + 1] = hits[src * 2 + 1] + (Math.random() - 0.5) * stride;
  }
  return out;
};

export const ParticleMesh = ({
  phrases,
  phraseDurationMs = 7200,
  pressure = 0.5,
  density = 1,
  reducedMotion = false,
  fontFamily = "DIN 1451",
  className = ""
}: ParticleMeshProps): JSX.Element => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const phrasesRef = useRef(phrases);
  const pressureRef = useRef(pressure);
  const densityRef = useRef(density);

  useEffect(() => {
    phrasesRef.current = phrases.length > 0 ? phrases : [""];
  }, [phrases]);
  useEffect(() => {
    pressureRef.current = pressure;
  }, [pressure]);
  useEffect(() => {
    densityRef.current = density;
  }, [density]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const gl = canvas.getContext("webgl", {
      alpha: true,
      antialias: false,
      premultipliedAlpha: false
    });
    if (!gl) return;

    const program = linkProgram(gl);
    if (!program) return;
    gl.useProgram(program);

    const aPosLoc = gl.getAttribLocation(program, "a_pos");
    const aLifeLoc = gl.getAttribLocation(program, "a_life");
    const uResLoc = gl.getUniformLocation(program, "u_resolution");
    const uSizeLoc = gl.getUniformLocation(program, "u_size");
    const uColorLoc = gl.getUniformLocation(program, "u_color");

    const dpr = Math.min(typeof window !== "undefined" ? window.devicePixelRatio || 1 : 1, 2);
    const particleCount = resolveParticleCount(densityRef.current);

    const positions = new Float32Array(particleCount * 2);
    const targets = new Float32Array(particleCount * 2);
    const velocities = new Float32Array(particleCount * 2);
    const lives = new Float32Array(particleCount);

    for (let i = 0; i < particleCount; i++) {
      lives[i] = 0.35 + Math.random() * 0.55;
    }

    const posBuffer = gl.createBuffer();
    const lifeBuffer = gl.createBuffer();

    gl.bindBuffer(gl.ARRAY_BUFFER, lifeBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, lives, gl.STATIC_DRAW);

    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    gl.clearColor(0, 0, 0, 0);

    gl.uniform3f(uColorLoc, 240 / 255, 248 / 255, 255 / 255);

    let phraseIndex = 0;
    let currentWidth = 0;
    let currentHeight = 0;

    const refreshTargets = (): void => {
      const list = phrasesRef.current;
      const text = list[phraseIndex % list.length] ?? "";
      const sampled = samplePhrasePositions(text, canvas.width, canvas.height, fontFamily, particleCount);
      targets.set(sampled);
    };

    const resize = (): void => {
      const w = window.innerWidth;
      const h = window.innerHeight;
      currentWidth = w;
      currentHeight = h;
      canvas.width = Math.floor(w * dpr);
      canvas.height = Math.floor(h * dpr);
      canvas.style.width = `${w}px`;
      canvas.style.height = `${h}px`;
      gl.viewport(0, 0, canvas.width, canvas.height);
      gl.uniform2f(uResLoc, canvas.width, canvas.height);
      gl.uniform1f(uSizeLoc, Math.max(1.6, dpr * 2.2));
      // Re-seed starting positions and sample current phrase into new canvas size.
      for (let i = 0; i < particleCount; i++) {
        positions[i * 2] = Math.random() * canvas.width;
        positions[i * 2 + 1] = Math.random() * canvas.height;
        velocities[i * 2] = 0;
        velocities[i * 2 + 1] = 0;
      }
      refreshTargets();
    };

    const drawOnce = (): void => {
      gl.bindBuffer(gl.ARRAY_BUFFER, posBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, positions, gl.DYNAMIC_DRAW);
      gl.enableVertexAttribArray(aPosLoc);
      gl.vertexAttribPointer(aPosLoc, 2, gl.FLOAT, false, 0, 0);

      gl.bindBuffer(gl.ARRAY_BUFFER, lifeBuffer);
      gl.enableVertexAttribArray(aLifeLoc);
      gl.vertexAttribPointer(aLifeLoc, 1, gl.FLOAT, false, 0, 0);

      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.drawArrays(gl.POINTS, 0, particleCount);
    };

    resize();
    window.addEventListener("resize", resize);

    if (reducedMotion) {
      positions.set(targets);
      drawOnce();
      return () => {
        window.removeEventListener("resize", resize);
        if (posBuffer) gl.deleteBuffer(posBuffer);
        if (lifeBuffer) gl.deleteBuffer(lifeBuffer);
        gl.deleteProgram(program);
      };
    }

    let frameId: number | null = null;
    let phraseTimer = phraseDurationMs;
    let lastTime = performance.now();

    const step = (now: number): void => {
      const dt = Math.min(48, now - lastTime);
      lastTime = now;
      phraseTimer -= dt;
      if (phraseTimer <= 0) {
        phraseIndex += 1;
        refreshTargets();
        phraseTimer = phraseDurationMs;
      }

      const p = pressureRef.current;
      const pull = 0.00085 + p * 0.0016;
      const friction = 0.9 + p * 0.035;
      const driftMag = 0.36 * (1 - p * 0.55);
      const tNow = now * 0.00055;

      for (let i = 0; i < particleCount; i++) {
        const ix = i * 2;
        const iy = ix + 1;
        const px = positions[ix];
        const py = positions[iy];
        const tx = targets[ix];
        const ty = targets[iy];
        let vx = velocities[ix];
        let vy = velocities[iy];
        vx += (tx - px) * pull * dt;
        vy += (ty - py) * pull * dt;
        vx += Math.sin(tNow + i * 0.137) * driftMag;
        vy += Math.cos(tNow * 0.87 + i * 0.211) * driftMag;
        vx *= friction;
        vy *= friction;
        positions[ix] = px + vx * dt * 0.045;
        positions[iy] = py + vy * dt * 0.045;
        velocities[ix] = vx;
        velocities[iy] = vy;
      }

      drawOnce();
      frameId = requestAnimationFrame(step);
    };

    frameId = requestAnimationFrame(step);

    return () => {
      if (frameId !== null) cancelAnimationFrame(frameId);
      window.removeEventListener("resize", resize);
      if (posBuffer) gl.deleteBuffer(posBuffer);
      if (lifeBuffer) gl.deleteBuffer(lifeBuffer);
      gl.deleteProgram(program);
      void currentWidth;
      void currentHeight;
    };
  }, [fontFamily, phraseDurationMs, reducedMotion]);

  return <canvas ref={canvasRef} className={className} aria-hidden="true" />;
};

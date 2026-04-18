import { stableHashToSeed } from "@conductor/protocol";

const pick = <T>(seed: number, slot: number, variants: T[]): T => {
  const derived = Math.abs(((seed >>> 0) * 2654435761 + slot * 2246822519) | 0);
  return variants[((derived >>> 0) % variants.length + variants.length) % variants.length];
};

const plotOpening = [
  "a reflection on the rejection of letting go as a formalized concept;",
  "a refusal to treat letting go as a skill one acquires;",
  "an inquiry into the impossibility of clean release;",
  "a work that treats letting go as a question rather than an answer;",
  "a sustained look at attachment as something other than failure;",
  "a rejection of the premise that loss resolves;"
];

const plotExplores = [
  "this variable length work explores representations of loss through a literal loss of directorial and temporal control as audience members govern and steer the work live.",
  "this variable length work stages three figures of persistence while distributing authorship across its audience in realtime.",
  "this variable length work opens a field of attachment and loss that its audience conducts, steers, and shapes live.",
  "this variable length work relinquishes the fixed timeline in favor of a conducted, audience-driven composition.",
  "this variable length work disperses its three subjects across a live system whose audience holds the controls."
];

const plotMethod = [
  "an ode to persistent ephemerality, this work applies aleatoric and improvisatory concepts to live video compositing.",
  "treating duration as a live material, the work applies aleatoric and improvisatory methods to video, text, and sound.",
  "the work applies chance operations and live improvisation to video compositing, producing a film that never settles into a fixed state.",
  "the film is procedural rather than fixed; its composition is determined live through chance, interaction, and operator control.",
  "applying aleatoric and improvisatory methods to cinema, the work produces a film whose form is never the same twice."
];

const plotScript = [
  "a script appears as text overlay, repeating from a tight set of phrases that mirror the repetitions of loss itself; the musical material does the same, cycling through a narrow sample bank.",
  "text from a script surfaces as overlay, cycling through a constrained phrase set; the sound material operates under the same constraint, drawn from a narrow bank of samples.",
  "a script repeats as text overlay, its phrases tight and recursive; the music mirrors this compression, looping through a small set of samples.",
  "text overlay draws from a recurring script; the musical palette is similarly constrained — a few samples turning over and over.",
  "script lines cycle as text overlay from a deliberately narrow set; the audio material is just as compressed, a tight bank of samples in constant rotation."
];

const plotReminders = [
  "these function as constant reminders, mirroring the strictures by which nostalgia and the ruminant reminders of what once was come to mind.",
  "these repetitions function as the work's memory — the way loss itself recurs, unbidden, in cycles that resist resolution.",
  "this constraint mirrors the mechanics of recollection itself: involuntary, recursive, operating on its own schedule.",
  "like memory, the repetitions arrive on their own terms — not summoned, not dismissed, just present.",
  "the repetitions are structural: they enact the way loss returns, not as event but as weather."
];

const plotClosing = [
  "things pass through us regardless of what we do for or against that; they don't lodge so much as circulate, pass through us.",
  "what remains does not lodge; it circulates, passes through, returns without permission.",
  "things stay with us not as wounds but as weather — passing through, returning, changing temperature.",
  "nothing is held or released cleanly; things pass through us, circulate, persist unevenly.",
  "there is no mechanism for clean release; things move through us at their own pace.",
  "things do not leave; they change speed, change temperature, but they do not leave."
];

const plotExtra: (string | null)[] = [
  null,
  null,
  "legacy persists far longer than memory.",
  "the film you see tonight has never been seen before and will never be seen again.",
  "each participant's version of this work is unique.",
  null,
  "there is no final cut.",
  null
];

const ethicRole = [
  "In this film, audience participation is somewhere between cast, crew, observer, operator, and director.",
  "In this film, the audience occupies a role that shifts between witness, co-author, and conductor.",
  "Here, the line between watching and making is deliberately unstable.",
  "In this film, the audience is not separate from the work — you are part of its nervous system.",
  "Participation in this film is not optional in the traditional sense; your presence is already compositional.",
  "In this work, the audience is neither passive nor fully in control — you are somewhere in between, and that is the point."
];

const ethicConstructs = [
  "I see this made manifest through two constructs: 1. the system itself, which, as a cybernetic system, provides a wide array of interactive surfaces between its nodes (you, me, the machines and servers, the film, etc.) and 2. that of \"the final cut\" which this film rejects, instead opting for an immanent, Deleuzian realization of film.",
  "This operates through two mechanisms: the cybernetic system itself, whose nodes — you, me, the machines, the network — form a web of mutual influence; and the rejection of \"the final cut,\" in favor of a film that is always in process.",
  "Two structures make this possible: a cybernetic network in which every participant, machine, and signal affects every other; and the refusal of finality — no version of this film is the definitive one.",
  "This emerges from a cybernetic architecture where every node influences every other, and from the principle that no version of this film is final.",
  "The system is cybernetic — you affect it, it affects you, the machines mediate — and the film has no final cut; it is always becoming."
];

const ethicBecoming = [
  "The latter treats the film as a constant process of becoming rather than a finished state, which connected audience-members shape live.",
  "The film is not an object but a process of becoming, shaped live by its connected audience.",
  "Rather than a finished state, the film exists as continuous emergence — audience-members compose it in the act of watching.",
  "The film never arrives at a final form; it is perpetually becoming, with its audience as co-composers.",
  "What you see is not a recording of a film; it is a film in the process of being made, with you inside it."
];

export const aboutPlotCopy = (hashedId: string): string => {
  const seed = stableHashToSeed(hashedId);
  const parts: (string | null)[] = [
    pick(seed, 0, plotOpening),
    " ",
    pick(seed, 1, plotExplores),
    " ",
    pick(seed, 2, plotMethod),
    " ",
    pick(seed, 3, plotScript),
    " ",
    pick(seed, 4, plotReminders),
    " ",
    pick(seed, 5, plotClosing)
  ];
  const extra = pick(seed, 6, plotExtra);
  if (extra) {
    parts.push(" ", extra);
  }
  return parts.join("");
};

export const aboutEthicCopy = (hashedId: string): string => {
  const seed = stableHashToSeed(hashedId);
  const parts = [
    pick(seed, 7, ethicRole),
    " ",
    pick(seed, 8, ethicConstructs),
    " ",
    pick(seed, 9, ethicBecoming)
  ];
  return parts.join("");
};

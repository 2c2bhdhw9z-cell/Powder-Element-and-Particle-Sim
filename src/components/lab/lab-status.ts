export type Mark = "done" | "live" | "soon";

export type LabItem = {
  name: string;
  mark: Mark;
  note: string;
};

export const LAB_STATUS: LabItem[] = [
  { name: "Powder + Particles, switch anytime", mark: "done", note: "Both rooms keep their stuff" },
  { name: "Real powder reactions", mark: "done", note: "Water, lava, ice, salt, fire…" },
  { name: "Particle controls + presets", mark: "done", note: "Galaxy, pour, flock, cloth…" },
  { name: "1,000,000 particle cap", mark: "done", note: "The lid is one million" },
  { name: "Playable swarm (smooth + collide)", mark: "live", note: "Fast pack for huge dumps" },
  { name: "Pour / water dots", mark: "live", note: "Bigger cup, still not an ocean" },
  { name: "Flock + hawk finger", mark: "live", note: "Hold to scare the birds" },
  { name: "Cloth rip + grab", mark: "live", note: "Pull it, stretch it, it tears" },
  { name: "Soft blob", mark: "live", note: "Jelly ring" },
  { name: "Fans any direction", mark: "live", note: "Paint over a fan to rotate it" },
  { name: "Gyro, recipes, encyclopedia", mark: "done", note: "Tilt, scenes, lore cards" },
  { name: "Split, undo, scene files", mark: "done", note: "Two rooms, one history" },
  { name: "Friends, same world", mark: "live", note: "Live room copies the powder world" },
  { name: "Circuit load", mark: "live", note: "Long copper overheats. Spark + C4 booms" },
  { name: "Vacuum room", mark: "live", note: "Recipe: sealed box, void eats the air" },
  { name: "Hawk tool", mark: "live", note: "Particles finger mode: they flee you" },
  { name: "See the net", mark: "live", note: "Cloth / rope / blob draw their strings" },
  { name: "Both clocks", mark: "live", note: "Timer icon. Off = hidden room sleeps" },
  { name: "Remix recipe", mark: "live", note: "Random scene plus extra junk" },
  { name: "Workshop maps + tags", mark: "live", note: "Publish / load / like / filter" },
  { name: "Rope", mark: "live", note: "Hang it, yank it, it snaps" },
  { name: "Shake the phone", mark: "live", note: "Gyro on, then shake — powder jumps" },
  { name: "Phone autosave", mark: "live", note: "Refresh keeps the lab. Menu can forget it" },
  { name: "Marble shove on the swarm", mark: "live", note: "Dots in the same cell bounce off each other" },
  { name: "Live room copies particles too", mark: "live", note: "Host sends a sample of the swarm" },
  { name: "Workshop hot/new feed", mark: "live", note: "Pictures, likes, plays, remix" },
  { name: "Editor presets + your list", mark: "live", note: "Goo / foam / slag. Delete your slots" },
  { name: "Beach / Forest / Kiln", mark: "live", note: "New powder recipes" },
  { name: "GPU marbles + own canvas", mark: "live", note: "Big dumps bounce twice, settle with friction" },
  { name: "Live follow actually draws", mark: "live", note: "Guest uploads the stream so it isn’t a blank pit" },
];

export function markGlyph(m: Mark) {
  if (m === "done") return "✅";
  if (m === "live") return "☑️";
  return "✔️";
}

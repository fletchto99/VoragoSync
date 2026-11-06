// Frozen test-only math reference from fletchto99/VoragoTag, src/timer.ts:
// https://github.com/fletchto99/VoragoTag/blob/1a995eb3781e4b245ddfa58483324291f59afc55/src/timer.ts
// Copyright (c) 2026 Matt Langlois. MIT License; see ../../LICENSE.
// DOM IDs and the unused audio constant are omitted; the math is unchanged.

export interface Section {
  label: string;
  duration: number;
  step: number;
}

export const SECTIONS: Section[] = [
  { label: "pre-ult", duration: 14.4, step: 0.6 },
  { label: "ult", duration: 0.6, step: 0.1 },
  { label: "post-ult", duration: 8.4, step: 0.6 },
  { label: "tc", duration: 0.6, step: 0.1 },
];

export const TOTAL_TIME = SECTIONS.reduce((total, s) => total + s.duration, 0);

export function sanitisePercentage(i: number): number {
  return Math.min(100, Math.max(0, i));
}

// Find the section a given remaining time falls in, measured from the end of
// the timer. Each window is inclusive at its top, so with the default schedule
// tc owns (0, 0.6], post-ult (0.6, 9.0], ult (9.0, 9.6] and pre-ult the rest.
export function activeSection(remaining: number): Section {
  let acc = 0;
  for (let i = SECTIONS.length - 1; i >= 0; i--) {
    acc += SECTIONS[i].duration;
    if (remaining <= acc) return SECTIONS[i];
  }
  return SECTIONS[0];
}

// Snap the raw remaining seconds to the step of whichever section is active.
export function snapRemainingSeconds(rawSecs: number): number {
  const secs = Math.max(0, rawSecs);
  const step = secs <= 0 ? SECTIONS[0].step : activeSection(secs).step;
  return Math.floor(secs / step + 1e-9) * step;
}

// Given the snapped remaining seconds, return the fill percentage for each
// section in left-to-right order.
export function sectionPercentages(secsNum: number): number[] {
  const elapsed = TOTAL_TIME - secsNum;
  let sectionStart = 0;
  return SECTIONS.map((section) => {
    const pct = sanitisePercentage(((elapsed - sectionStart) / section.duration) * 100);
    sectionStart += section.duration;
    return pct;
  });
}

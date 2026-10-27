import type { CSSProperties, ReactNode } from "react";

// Colours for SGR 30–37 / 90–97 (fg) on the dark log terminal.
const PALETTE = [
  "#6f6f6f", "#ff8389", "#42be65", "#f1c21b",
  "#78a9ff", "#d4bbff", "#3ddbd9", "#e0e0e0",
];
const BRIGHT = [
  "#a8a8a8", "#ffb3b8", "#6fdc8c", "#fddc69",
  "#a6c8ff", "#e8daff", "#9ef0f0", "#ffffff",
];

// Any CSI sequence: SGR (`m`) is styled, the rest (cursor moves, erase) is
// dropped so it doesn't show up as garbage.
// eslint-disable-next-line no-control-regex -- matching ESC is the point
const CSI = /\x1b\[([0-9;?]*)([A-Za-z])/g;

/// Renders [text] with its ANSI colours and bold as styled spans. The text
/// stays text: nothing is interpreted as HTML.
export function renderAnsi(text: string): ReactNode {
  if (!text.includes("\x1b")) return text;
  const out: ReactNode[] = [];
  let style: CSSProperties = {};
  let last = 0;
  let key = 0;
  const push = (chunk: string) => {
    if (!chunk) return;
    out.push(
      Object.keys(style).length ? (
        <span key={key++} style={style}>
          {chunk}
        </span>
      ) : (
        chunk
      ),
    );
  };
  for (const m of text.matchAll(CSI)) {
    push(text.slice(last, m.index));
    last = (m.index ?? 0) + m[0].length;
    if (m[2] !== "m") continue;
    const codes = m[1] === "" ? [0] : m[1].split(";").map(Number);
    for (const c of codes) {
      if (c === 0) style = {};
      else if (c === 1) style = { ...style, fontWeight: 600 };
      else if (c === 22) style = { ...style, fontWeight: undefined };
      else if (c >= 30 && c <= 37) style = { ...style, color: PALETTE[c - 30] };
      else if (c >= 90 && c <= 97) style = { ...style, color: BRIGHT[c - 90] };
      else if (c === 39) style = { ...style, color: undefined };
    }
  }
  push(text.slice(last));
  // Stray ESC characters from partial sequences.
  return out.map((n) =>
    // eslint-disable-next-line no-control-regex -- stray ESC characters
    typeof n === "string" ? n.replace(/\x1b/g, "") : n,
  );
}

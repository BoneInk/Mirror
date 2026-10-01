export const themes = [
  [
    "light",
    "Mirror Light",
    false,
    "#FFFFFF",
    "#2D2D2D",
    "#707070",
    "#D8D8D8",
    "#AE542F",
    "#F5F5F5",
  ],
  [
    "dark",
    "Mirror Dark",
    true,
    "#252420",
    "#EEEAE0",
    "#B3ACA0",
    "#514C43",
    "#C4B59A",
    "#302E29",
  ],
  [
    "sepia",
    "Sepia",
    false,
    "#F5E9CA",
    "#3C3325",
    "#85745C",
    "#DFCFAA",
    "#8B5B32",
    "#EADBB8",
  ],
  [
    "midnight",
    "Midnight",
    true,
    "#16181C",
    "#D7DBDF",
    "#858C94",
    "#2D3138",
    "#68C7B3",
    "#22262C",
  ],
  [
    "solarized",
    "Solarized Light",
    false,
    "#FDF6E3",
    "#586E75",
    "#839496",
    "#EEE8D5",
    "#268BD2",
    "#EEE8D5",
  ],
  [
    "nord",
    "Nord",
    true,
    "#2E3440",
    "#D8DEE9",
    "#8993A5",
    "#434C5E",
    "#88C0D0",
    "#3B4252",
  ],
  [
    "dracula",
    "Dracula",
    true,
    "#282A36",
    "#F8F8F2",
    "#9CA0B0",
    "#44475A",
    "#BD93F9",
    "#343746",
  ],
  [
    "forest",
    "Forest",
    true,
    "#17231D",
    "#DCE7DF",
    "#8DA096",
    "#32483C",
    "#78C59A",
    "#223129",
  ],
  [
    "rose",
    "Rose",
    false,
    "#FFF8F7",
    "#402F32",
    "#8F7479",
    "#EEDDDD",
    "#B44B68",
    "#F7EAEA",
  ],
].map(([id, name, dark, background, text, muted, line, accent, code]) => ({
  id,
  name,
  dark,
  background,
  text,
  muted,
  line,
  accent,
  code,
}));
export function selectedTheme(config, systemDark) {
  return (
    [...themes, ...(config.customThemes || [])].find(
      (theme) =>
        theme.id ===
        (config.theme === "system"
          ? systemDark
            ? "dark"
            : "light"
          : config.theme),
    ) || themes[0]
  );
}
export function themeStyle(theme) {
  return {
    "--paper": theme.background,
    "--text": theme.text,
    "--fg": theme.text,
    "--muted": theme.muted,
    "--line": `${theme.line}70`,
    "--accent": theme.accent,
    "--code": theme.code,
    "--bg": theme.code,
    "--navigation": theme.background,
    "--hover": `${theme.accent}0d`,
    "--accent-soft": `${theme.accent}12`,
  };
}

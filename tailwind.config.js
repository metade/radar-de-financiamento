module.exports = {
  content: [
    "./*.{html,md}",
    "./_includes/**/*.{html,md}",
    "./_layouts/**/*.{html,md}",
    "./_reports/**/*.{html,md}"
  ],
  theme: {
    extend: {
      colors: {
        ink: "#172033",
        "civic-blue": "#0f5f8f",
        "civic-green": "#2f7d57",
        "civic-gold": "#a86d00",
        "soft-sky": "#eef7fb",
        "soft-mint": "#eff8f1",
        "soft-amber": "#fff7e6",
        "line": "#d6dde5"
      },
      fontFamily: {
        sans: ["Inter", "ui-sans-serif", "system-ui", "sans-serif"]
      }
    }
  },
  plugins: []
}

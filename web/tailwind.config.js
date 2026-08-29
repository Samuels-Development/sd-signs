/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  // The panel is hand-written CSS (src/styles.css). Preflight is disabled so
  // Tailwind's reset cannot fight it; Tailwind is only here for stray utilities.
  corePlugins: { preflight: false },
  theme: { extend: {} },
  plugins: [],
};

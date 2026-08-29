import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath, URL } from 'node:url';

// Build the sign builder into web/build with relative asset paths so the
// FiveM NUI (nui://sd-signs/web/build/index.html) resolves them. Filenames
// are unhashed to match the lean fxmanifest files{} globs.
export default defineConfig({
  plugins: [react()],
  base: './',
  // '@' -> src, so cross-area imports read `@/i18n` instead of `../../../i18n`.
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  build: {
    outDir: 'build',
    emptyOutDir: true,
    assetsDir: 'assets',
    target: 'chrome108',
    rollupOptions: {
      output: {
        entryFileNames: 'assets/[name].js',
        chunkFileNames: 'assets/[name].js',
        assetFileNames: 'assets/[name].[ext]',
      },
    },
  },
});

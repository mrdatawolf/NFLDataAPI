import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import dotenv from 'dotenv';

dotenv.config();

const devPort = Number(process.env.DEVPORT || 5174);
const apiPort = Number(process.env.APIPORT || 3002);

export default defineConfig({
  root: fileURLToPath(new URL('.', import.meta.url)),
  plugins: [react()],
  server: {
    port: devPort,
    proxy: {
      '/api': `http://localhost:${apiPort}`
    }
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true
  }
});

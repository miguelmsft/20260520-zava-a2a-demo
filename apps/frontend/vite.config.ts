import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Vite dev server on :5173 with /api proxied to FastAPI backend on :8000.
// SSE streaming requires changeOrigin + ws disabled (HTTP/1.1 long-lived).
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      '/api': {
        target: 'http://localhost:8000',
        changeOrigin: true,
        ws: false,
      },
    },
  },
});

# syntax=docker/dockerfile:1

FROM node:22.19.0-bookworm-slim AS server-build
WORKDIR /app/server
COPY server/package.json server/package-lock.json ./
RUN npm ci
COPY server/ ./
RUN npm run build

FROM node:22.19.0-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8080
ENV WEB_ROOT=/app/client/build
COPY --from=server-build /app/server/package.json /app/server/package-lock.json ./server/
COPY --from=server-build /app/server/node_modules ./server/node_modules
COPY --from=server-build /app/server/dist ./server/dist
COPY --from=server-build /app/server/public ./server/public
COPY client/ui/phone_remote.html ./client/ui/phone_remote.html
COPY client/build ./client/build
WORKDIR /app/server
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||8080)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "dist/index.js"]

FROM node:22-alpine

WORKDIR /app

COPY services/worker /app/services/worker

CMD ["node", "/app/services/worker/index.mjs"]

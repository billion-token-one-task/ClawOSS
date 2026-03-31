FROM node:22-alpine

WORKDIR /app

COPY services/reflection /app/services/reflection

CMD ["node", "/app/services/reflection/index.mjs"]

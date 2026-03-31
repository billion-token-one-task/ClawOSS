FROM node:22-alpine

WORKDIR /app

COPY package.json package-lock.json ./
COPY dashboard/package.json dashboard/package.json
RUN npm ci

COPY . .

RUN npm run dashboard:build

WORKDIR /app/dashboard
ENV NODE_ENV=production
EXPOSE 3000

CMD ["npm", "run", "start"]

FROM node:20-alpine

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --production

COPY index.js .

EXPOSE ${PORT:-3000}

CMD ["node", "index.js"]

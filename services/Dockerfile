FROM node:20.18.1-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY *.js ./
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser
ARG PORT=3001
EXPOSE ${PORT}
CMD ["node", "index.js"]

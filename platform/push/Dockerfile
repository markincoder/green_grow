FROM node:20-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY src ./src
ENV DATA_DIR=/data
ENV STATIC_DIR=/var/www
ENV PORT=3000
VOLUME ["/data", "/var/www"]
EXPOSE 3000
CMD ["npm", "start"]

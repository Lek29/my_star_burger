FROM node:18

WORKDIR /app

COPY package*.json ./

RUN npm install

COPY . .

CMD ["./node_modules/.bin/parcel", "watch", "bundles-src/index.js", "--dist-dir", "bundles", "--public-url", "./"]

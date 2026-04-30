FROM node:16-alpine AS build

WORKDIR /app

COPY package*.json ./
RUN npm ci --legacy-peer-deps

COPY . .

ARG REACT_APP_API_SERVER=/api/
ENV REACT_APP_API_SERVER=${REACT_APP_API_SERVER}

RUN npm run build

FROM nginx:1.25-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build /usr/share/nginx/html

EXPOSE 80

CMD ["sh", "-c", "sed -i '/^[0-9a-fA-F:]*:[0-9a-fA-F:].* backend/d' /etc/hosts 2>/dev/null || true; exec nginx -g 'daemon off;'"]
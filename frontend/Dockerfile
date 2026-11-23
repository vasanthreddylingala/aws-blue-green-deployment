# ==========================================
# STAGE 1: Build React Assets
# ==========================================
FROM node:18-alpine AS builder

WORKDIR /app

# Cache dependency layer
COPY package.json ./
RUN npm install

# Build static production bundle
COPY . ./
RUN npm run build

# ==========================================
# STAGE 2: High Performance Nginx Web Server
# ==========================================
FROM nginx:alpine

# Remove default Nginx website
RUN rm -rf /usr/share/nginx/html/*

# Copy compiled static assets from Stage 1
COPY --from=builder /app/build /usr/share/nginx/html

# Copy custom Nginx reverse proxy configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]

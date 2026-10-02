FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

ARG API_BASE_URL
ARG ALLOW_INSECURE_API=false

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN test -n "$API_BASE_URL" \
    || (echo "Informe --build-arg API_BASE_URL=https://seu-endereco" >&2; exit 1)
RUN flutter build web --release \
    --dart-define=API_BASE_URL=$API_BASE_URL \
    --dart-define=ALLOW_INSECURE_API=$ALLOW_INSECURE_API

FROM nginx:alpine AS producao

COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

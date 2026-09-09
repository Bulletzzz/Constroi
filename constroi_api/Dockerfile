FROM dart:stable AS build

WORKDIR /app

COPY pubspec.* ./
RUN dart pub get

COPY . .
RUN dart pub global activate dart_frog_cli 1.2.14
RUN dart pub global run dart_frog_cli:dart_frog build

WORKDIR /app/build
RUN dart pub get --offline
RUN dart compile exe bin/server.dart -o /servidor

FROM debian:bookworm-slim AS producao

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

COPY --from=build /servidor /app/servidor

ENV PORT=8080
EXPOSE 8080

CMD ["/app/servidor"]

FROM dart:stable AS build

WORKDIR /app

# Copy core package first (dependency)
COPY packages/spoomn_core/pubspec.yaml packages/spoomn_core/pubspec.yaml
COPY packages/spoomn_core/ packages/spoomn_core/

# Copy server package
COPY packages/spoomn_server/pubspec.yaml packages/spoomn_server/pubspec.yaml

WORKDIR /app/packages/spoomn_server
RUN dart pub get

COPY packages/spoomn_server/ .

# AOT compile for fast startup
RUN dart compile exe bin/server.dart -o bin/server

# Minimal runtime image
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/packages/spoomn_server/bin/server /app/server

EXPOSE 8080

CMD ["/app/server"]

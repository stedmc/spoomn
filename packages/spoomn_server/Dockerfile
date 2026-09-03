FROM dart:stable AS build

WORKDIR /app

COPY packages/spoomn_core/pubspec.yaml packages/spoomn_core/pubspec.yaml
COPY packages/spoomn_core/pubspec.lock packages/spoomn_core/pubspec.lock
COPY packages/spoomn_core/ packages/spoomn_core/

WORKDIR /app/packages/spoomn_core
RUN dart pub get
RUN dart run build_runner build

COPY packages/spoomn_server/pubspec.yaml packages/spoomn_server/pubspec.yaml
COPY packages/spoomn_server/pubspec.lock packages/spoomn_server/pubspec.lock

WORKDIR /app/packages/spoomn_server
RUN dart pub get

COPY packages/spoomn_server/ .

RUN dart compile exe bin/server.dart -o bin/server

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/packages/spoomn_server/bin/server /app/server

EXPOSE 8080

CMD ["/app/server"]

FROM dart:stable AS build

WORKDIR /app

COPY packages/spoomn_core/pubspec.yaml packages/spoomn_core/pubspec.yaml
COPY packages/spoomn_core/pubspec.lock packages/spoomn_core/pubspec.lock
COPY packages/spoomn_core/ packages/spoomn_core/

COPY packages/spoomn_server/pubspec.yaml packages/spoomn_server/pubspec.yaml
COPY packages/spoomn_server/pubspec.lock packages/spoomn_server/pubspec.lock

RUN cd packages/spoomn_core && dart pub get && dart run build_runner build

RUN cd packages/spoomn_server && dart pub get

COPY packages/spoomn_server/ packages/spoomn_server/

RUN cd packages/spoomn_server && dart compile exe bin/server.dart -o bin/server

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/packages/spoomn_server/bin/server /app/server

EXPOSE 8080

CMD ["/app/server"]

FROM dart:stable AS build
WORKDIR /app
RUN apt-get update
RUN apt-get install -y libsqlite3-dev
RUN rm -rf /var/lib/apt/lists/*
COPY backend ./backend
COPY packages/helix_remote_domain ./packages/helix_remote_domain
RUN sed -i '/resolution: workspace/d' backend/pubspec.yaml
RUN sed -i '/resolution: workspace/d' packages/helix_remote_domain/pubspec.yaml
WORKDIR /app/backend
RUN dart pub get
RUN dart build cli --target=bin/server.dart --output=/app/out

FROM debian:bookworm-slim
RUN apt-get update
RUN apt-get install -y libsqlite3-dev ca-certificates
RUN rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/out/bundle /app/bundle
EXPOSE 8080
CMD ["/app/bundle/bin/server"]

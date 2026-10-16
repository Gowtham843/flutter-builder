# Flutter Builder

## Build the Docker image

The image pre-warms Flutter Pub and Gradle/Maven caches from one reference
portal app. Supply that app as a named BuildKit context:

```bash
docker build \
  --build-context reference-app=/path/to/some/portal/app \
  -t flutter-builder .
```

`reference-app` must point directly to a Flutter app directory containing
`pubspec.yaml` and `android/`. This requires Docker 23+ with BuildKit.

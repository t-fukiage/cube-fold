# cube_fold

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Local Web Testing (GitHub Pages)

This project is deployed to GitHub Pages under `/cube-fold/`. To test the same
path locally, use the script below:

```bash
./scripts/serve_ghpages.sh
# open http://localhost:8000/cube-fold/
```

Options:

- Use a different port:
  ```bash
  ./scripts/serve_ghpages.sh 8001
  ```
- Override the base href:
  ```bash
  ./scripts/serve_ghpages.sh 8000 /cube-fold/
  ```

# Deprecated: Google OAuth setup

This project no longer recommends Google service-account JSON credentials for pub.dev publishing.

Use **pub.dev trusted publishing / GitHub OIDC** instead:

1. Configure the package trusted publisher in pub.dev for repository `pvagnozzi/platform_serial`.
2. Set workflow `.github/workflows/publish-release.yml`.
3. Set GitHub environment `pub-dev`.
4. Merge a release PR into `main` or run the protected manual workflow.

See [`GITHUB_SETUP.md`](./GITHUB_SETUP.md) and [`GITFLOW.md`](./GITFLOW.md).

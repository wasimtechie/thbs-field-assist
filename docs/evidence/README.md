# Local verification output

This folder holds locally generated test logs, UI captures, package reports and device diagnostics. Those outputs are excluded from source control. Keep authentication state, private configuration and raw device diagnostics local.

Source checks and repeatable workflows are documented in the repository README and `docs/design/`. Dashboard/API checks are in `scripts/`, Flutter tests are in `apps/mobile/test/` and `apps/mobile/integration_test/`, and product-film checks are in `apps/product-demo/scripts/`.

The product demo's required screenshots, fonts, avatars and narration are already included under `apps/product-demo/public/`; rendering does not depend on this evidence directory. APKs and rendered videos are generated delivery artifacts and are not part of the source repository.

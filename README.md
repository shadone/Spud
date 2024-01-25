# Spud, native iOS app for Lemmy.

Spud (placeholder name) is a client for [Lemmy](https://join-lemmy.org).

## Development setup

### Install `mint`

We use [mint](https://github.com/yonaskolb/Mint) tool to run Swift cli packages such as `SwiftGen`.

```sh
brew install mint
```

Then install the cli packages that we use as part of the build process.

```sh
mint bootstrap
```

### Install pre-commit hook

See [scripts/git-hooks/README.md](scripts/git-hooks/README.md)

### Snapshot tests

[Swift Snapshot Testing](https://github.com/pointfreeco/swift-snapshot-testing) library is used
to take screenshots for testing. To run the tests switch to "SpudSnapshot" test plan and run
against "iPhone 14 Pro" simulator (ensure the simulator window is in portrait orientation!).

## License

Spud is licensed under a 2-clause BSD license. See LICENSE for details.

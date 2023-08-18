# Spud, native iOS app for Lemmy.

Spud (placeholder name) is a client for [Lemmy](https://join-lemmy.org).

## Development setup

### SwiftGen

Install [SwiftGen](https://github.com/SwiftGen/SwiftGen) from Homebrew:

```sh
$ brew install swiftgen
```

The swiftgen is invoked automatically during the build process.

### Snapshot tests

[Swift Snapshot Testing](https://github.com/pointfreeco/swift-snapshot-testing) library is used
to take screenshots for testing. To run the tests switch to "SpudSnapshot" test plan and run
against "iPhone 14 Pro" simulator (ensure the simulator window is in portrait orientation!).

## License

Spud is licensed under a 2-clause BSD license. See LICENSE for details.

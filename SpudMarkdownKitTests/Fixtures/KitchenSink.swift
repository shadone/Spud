//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// A realistic Lemmy post exercising every supported element, ported from the
/// design reference (`md-content.jsx`). Used as the parser's golden fixture.
enum KitchenSink {
    static let post = """
        Valve **finally** shipped a flashable SteamOS image, so I put it on a Legion Go. Short version: it's *very* good, with ~~three~~ two real rough edges. Ping me (@glidergun@lemmy.world) or drop into !linux_gaming@lemmy.world. :penguin:

        Tested build: `steamos-3.7.8`. Recovery image: https://store.steampowered.com/steamos/download

        # H1 — Section title
        ## H2 — Subsection

        You'll want, in rough order:

        - A USB-C drive, **8 GB or larger**.
        - The official `rufus` flasher.
            - Save files sync via cloud.
            - Screenshot your BIOS first.

        Steps:

        1. Disable Secure Boot.
        2. Flash the recovery image.
        3. Choose **Reimage** or **Repair**.

        | Subsystem | Claimed | Measured | OK? |
        |:---|---:|---:|:---:|
        | Suspend/resume | < 2s | 1.4s | yes |
        | Fingerprint | Yes | No driver | no |

        Drop this in your config:

        ```bash
        export ALSA_CARD=acp
        pactl set-sink-volume @DEFAULT_SINK@ 140%
        ```

        > Third-party support is **best-effort**.
        >
        > > The fingerprint reader may never work.

        ![SteamOS desktop on the Legion Go](https://lemmy.world/pictrs/image/desktop.png)

        ![suspend clip](https://lemmy.world/pictrs/video/suspend.mp4)

        ::: spoiler Cyberpunk 2077 — ultra
        :::

        ::: spoiler Elden Ring — settled numbers
        Locked **60 fps** at 800p medium.
        :::

        ---

        Formatting test: H~2~O, E=mc^2^, "smart quotes," en--dashes, em---dashes, ellipsis... Corrections welcome.[^1]

        [^1]: If the checksum doesn't match, **stop** — re-download over a wired connection.
        """
}

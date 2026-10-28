# Shopping Planner

> Working title. Plan big purchases and stay on budget.

[![CI](https://github.com/alx-artm/ShoppingPlanner/actions/workflows/ci.yml/badge.svg)](https://github.com/alx-artm/ShoppingPlanner/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-iOS-lightgrey)
![Swift](https://img.shields.io/badge/Swift-SwiftUI%20%7C%20SwiftData-orange)

An iPhone app for planning purchases with a budget — a kids' room renovation, a move, gifts, a trip.
Organize a project into groups (furniture, materials, decor), add items with price and quantity,
check them off as you buy, and always see what's spent and what's left.

> **Status:** in active development towards v1.0 on the App Store. Screenshots will be added with the redesign.

## Features

- Lists with icon, color and pinning
- Collapsible groups with per-group and per-list totals
- Items with price × quantity, link and notes; completed items sorted to the bottom
- Light / dark / system theme

### Planned for v1.0

- iCloud sync across devices (SwiftData + CloudKit)
- Budget per list and a main currency
- Product link previews and a Share Extension to add items straight from Safari or a store app
- Adaptive layout for iPhone, the foldable iPhone and iPad (`NavigationSplitView`)
- English and Russian localization, full Dynamic Type and VoiceOver support

## Tech stack

| | |
|---|---|
| UI | SwiftUI |
| Persistence | SwiftData |
| Tests | Swift Testing, XCUITest |
| CI | GitHub Actions |

## Requirements

- Xcode 26 or later
- iOS 26.0+ (iPhone and iPad)

## Getting started

```bash
git clone https://github.com/alx-artm/ShoppingPlanner.git
cd ShoppingPlanner
open Project2.xcodeproj
```

Select the `Project2` scheme and an iPhone simulator, then run (⌘R). Run the unit and UI tests with ⌘U.
To run on a device, set your own team in *Signing & Capabilities*.

## Project structure

```
Project2/
├── Models/   SwiftData models and sample data
└── Views/    SwiftUI screens and components
Project2Tests/    Unit tests (Swift Testing)
Project2UITests/  UI tests (XCUITest)
```

## License

Copyright © 2025–2026 Aleksei Artimuck. All rights reserved. The source is published for portfolio
and review purposes only — see [LICENSE](LICENSE).

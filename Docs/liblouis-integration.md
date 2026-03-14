# Liblouis integration in Anvill

Anvill embeds Liblouis directly inside the project repository and exposes it to Swift using a bridging header.

This means contributors do not need to install Liblouis separately through Homebrew or any other package manager before building the project.

## Why this approach was chosen

Many projects rely on a system-installed copy of Liblouis. That often causes unnecessary build problems.

Anvill keeps Liblouis inside the repository so the project is easier to clone, build, run, and contribute to.

## What is included

`The project includes:

- Liblouis inside the repository
- the required headers
- translation tables
- a bridging header for Swift

## How it works

Liblouis is a C library. Swift accesses it through a bridging header.

The bridging header exposes the Liblouis header to Swift.

Example:

```c
#include "liblouis.h"

Once that is set up in the Xcode project, Swift code can call the Liblouis API directly.

Build behaviour After cloning the repository: 1. Open the Xcode project. 2. Build the project. 3. Run the app. 4. Paste text into the input field. 5. ASCII Braille output appears in the result field. No external Liblouis installation is required. Why this matters Liblouis integration in Swift can be difficult because of: •	bridging header configuration
	•	header search paths
	•	C library integration in Xcode Anvill already contains a working setup, which makes the project easier for future contributors to understand and extend.
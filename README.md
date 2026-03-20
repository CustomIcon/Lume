# Lume

A modern, native Jellyfin client for macOS, designed with a focus on aesthetics, performance, and the native Mac experience.

![Home Screen](screenshots/Home.png)

## 🌟 Features

*   **Native & Fast**: Built from the ground up with **SwiftUI** and **SwiftData** for a lightning-fast, resource-efficient experience.
*   **VLC Playback Engine**: Powered by **VLCKit** for robust support of virtually any video format, including advanced subtitle rendering and audio track switching.
*   **Aesthetic "Liquid" Design**: A premium interface featuring glassmorphism, smooth animations, and a cohesive "liquid" design system that feels right at home on macOS.
*   **Smart Library Management**: Effortlessly browse your Movies, TV Shows, and Music libraries with native grid views and detailed metadata.
*   **Custom Themes**: Choose from multiple curated themes (Dark, Light, Slate, Forest, and more) to match your workspace.
*   **Automated Content Discovery**: Intelligent "Continue Watching" and "Recently Added" sections keep your favorite media front and center.

## 📸 Screenshots

| Home | Movies |
| :---: | :---: |
| ![Home](screenshots/Home.png) | ![Movies](screenshots/Movies.png) |

| Music | Search |
| :---: | :---: |
| ![Music](screenshots/Music.png) | ![Search](screenshots/Search.png) |

| Settings | Onboarding |
| :---: | :---: |
| ![Settings](screenshots/Settings.png) | ![Onboarding](screenshots/OnBoarding.png) |

## 🚀 Getting Started

### Prerequisites

*   macOS 14.0 or later.
*   A running **Jellyfin** server access.

### Installation

1.  Download the latest **Lume.dmg** from the [Releases](https://git.cubable.date/CustomIcon/Lume/releases) page.
2.  Open the DMG and drag **Lume** to your **Applications** folder.
3.  Open up `Terminal` and run the following command: `xattr -d com.apple.quarantine /Applications/Lume.app`
4.  Launch Lume and enter your server URL to begin the onboarding process.

## 🛠 Development

Lume is built with modern Apple technologies:

*   **SwiftUI**: For the entire user interface.
*   **SwiftData**: For local persistence and caching.
*   **VLCKit**: For the media playback engine.
*   **SessionManager**: Custom logic for managing Jellyfin API interactions.

### Building from Source

1.  Clone the repository:
    ```bash
    git clone https://git.cubable.date/CustomIcon/Lume.git
    ```
2.  Open `Lume.xcodeproj` in **Xcode 15.0+**.
3.  Ensure the **VLCKit** Swift Package is resolved.
4.  Build and Run (`Cmd + R`).

## 📄 AI / LLM usage DISCLAIMER

This project is partially developed with the help of AI. Such as Documenting functions, VLCKit implemetation and This very README.md file was also generated with the help of AI. other than that, all the code was written by either me or a contributor.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

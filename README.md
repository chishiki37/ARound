# ARound

**Look around. Hear the story.**

ARound is an audio guide for Meta Ray-Ban smart glasses. Put the glasses on, ask "What am I looking at?", and a guide that sees through your glasses and knows where you are answers in your ear.

The name is three words in one: **AR**, **around**, and **sound**.

> ARound is a personal, build-it-yourself project. It is not on the App Store. You install it on your own iPhone from Xcode, with your own API key. It runs on the developer preview of Meta's Wearables Device Access Toolkit, so expect rough edges.

## What it does

- **Sees what you see.** Frames from the glasses camera go to the AI guide while it is listening.
- **Knows where you are.** Your phone's GPS position, the nearest address and your walking direction are passed to the guide.
- **Knows what is nearby.** The app looks up named places around you (Apple Maps and Wikipedia) and gives the guide a shortlist to match against the camera view.
- **Guide packs.** Curated places with checked stories, written visual descriptions and your own reference photos. Packs work without a connection.
- **Photo matching.** The camera view is compared, on the phone, with reference photos of nearby pack places.
- **Hands-free.** Say "Hey ARound" to wake it, "go to sleep" to mute it, or tap the side of your glasses to pause everything.
- **Your choice of AI.** Gemini Live by default, or the OpenAI Realtime API with your own key.

## Quick start

1. Install Xcode 16 or later on a Mac, and pair your glasses with the Meta AI app on an iPhone running iOS 17 or later.
2. Clone this repository and open `samples/CameraAccess/CameraAccess.xcodeproj`.
3. Copy `CameraAccess/Secrets.swift.example` to `CameraAccess/Secrets.swift` and paste in a [Gemini API key](https://aistudio.google.com/apikey).
4. In **Signing & Capabilities**, choose your team and set a bundle identifier of your own.
5. Turn on Developer Mode in the Meta AI app and on your iPhone.
6. Select your iPhone and press **Cmd+R**.

The full walkthrough, with every account and setting you need, is in **[docs/SETUP.md](docs/SETUP.md)**.

## Documentation

| Guide | What it covers |
|---|---|
| [docs/SETUP.md](docs/SETUP.md) | Apple account, Xcode, iPhone Developer Mode, Gemini key, Meta glasses setup, first run, troubleshooting |
| [docs/FEATURES.md](docs/FEATURES.md) | How to use the guide: questions, wake phrase, pausing, location, settings, privacy |
| [docs/PACKS.md](docs/PACKS.md) | What packs are, available packs, installing them, and how to write your own |

## Guide packs

| Pack | Places | Download |
|---|---|---|
| Singapore Civic District and River | 12 | [pack-singapore-civic-district.json](packs/pack-singapore-civic-district.json) |

This pack is also built into the app. See [docs/PACKS.md](docs/PACKS.md) to make your own.

## Project layout

```
docs/                         Setup, features and pack guides
packs/                        Downloadable guide packs
samples/CameraAccess/         The Xcode project
  CameraAccess/Gemini/        Gemini Live connection, audio, session logic, guide instructions
  CameraAccess/OpenAI/        OpenAI Realtime connection, location, nearby places, packs,
                              photo matching, wake phrase, theme
  CameraAccess/Settings/      Settings storage and screen
  CameraAccess/Views/         Home and guide screens
  CameraAccess/WebRTC/        Optional live streaming of your view to a browser
  server/                     Optional signaling server for live streaming
```

## Status and limits

- Built and tested by one person on one phone and one pair of glasses. Several features have had little field testing.
- Not a navigation or safety aid. It does not give directions or warn about hazards.
- The guide can be wrong. It is told to say when it is unsure, and curated packs reduce mistakes, but always treat answers as a starting point.
- "What did I just walk past?", guided tours and audio stories are planned but not built.

## Credits and licence

ARound is adapted from [VisionClaw](https://github.com/Intent-Lab/VisionClaw), which is built on Meta's CameraAccess sample for the [Wearables Device Access Toolkit](https://github.com/facebook/meta-wearables-dat-ios). Use of the toolkit is subject to the [Meta Wearables Developer Terms](https://wearables.developer.meta.com/terms) and [Acceptable Use Policy](https://wearables.developer.meta.com/acceptable-use-policy); see [LICENSE](LICENSE) and [NOTICE](NOTICE).

Facts in the Singapore pack come from English Wikipedia and are used under CC BY-SA 4.0. Sources are listed inside the pack file.

ARound is not affiliated with or endorsed by Meta, Google, OpenAI or Apple.

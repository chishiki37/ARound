# Setting up ARound

This guide takes you from nothing to a working audio guide on your own iPhone and glasses. Allow about an hour the first time. Most of that is downloads.

## What you need

| You need | Notes |
|---|---|
| A Mac with Xcode 16 or later | Free from the Mac App Store |
| An iPhone running iOS 17 or later | With a cable to connect it to the Mac |
| Meta Ray-Ban glasses supported by Meta's Device Access Toolkit | Check Meta's [version dependencies](https://wearables.developer.meta.com/docs/develop/dat/version-dependencies/) page for supported models and software versions |
| The Meta AI app on that iPhone | With the glasses already paired and updated |
| An Apple ID | A free one works; see step 1 |
| A Google account | For the Gemini API key |

You do not need a Meta developer account to run ARound on your own glasses in Developer Mode.

## 1. Apple account

You sign the app with an Apple ID so your iPhone will run it.

- **Free Apple ID.** Works for your own phone. Apps you install this way stop opening after 7 days, and you reinstall from Xcode to renew them.
- **Apple Developer Program** (paid, yearly). Apps last a year and you can share test builds. Join at [developer.apple.com/programs](https://developer.apple.com/programs/). You do not need this to try ARound.

Add your account to Xcode: **Xcode > Settings > Accounts > +**, then choose **Apple ID** and sign in.

## 2. Get the code

```bash
git clone https://github.com/chishiki37/ARound.git
cd ARound/samples/CameraAccess
open CameraAccess.xcodeproj
```

The first time the project opens, Xcode downloads two packages (Meta's wearables toolkit and WebRTC). Wait for "Resolving packages" in the status bar to finish.

## 3. Gemini API key

1. Go to [aistudio.google.com/apikey](https://aistudio.google.com/apikey) and sign in with a Google account.
2. Choose **Create API key** and copy it.
3. In Terminal, from `samples/CameraAccess`:

   ```bash
   cp CameraAccess/Secrets.swift.example CameraAccess/Secrets.swift
   ```

4. Open `CameraAccess/Secrets.swift` in Xcode and replace `YOUR_GEMINI_API_KEY` with your key.

`Secrets.swift` is ignored by git, so your key is never committed. The project will not build until this file exists.

You can also leave the placeholder and paste the key later in the app under **Settings > AI Provider**. Check Google's current pricing and free allowance for the Gemini Live API before long sessions.

### Optional: OpenAI instead of Gemini

ARound can use the OpenAI Realtime API. This needs an API key from [platform.openai.com/api-keys](https://platform.openai.com/api-keys) with API billing set up. A ChatGPT subscription does not include API use. Enter the key in the app under **Settings > AI Provider > OpenAI**. The OpenAI path has had less testing than Gemini.

## 4. Signing in Xcode

1. Click the blue project icon at the top of the left sidebar.
2. Select the **CameraAccess** target, then the **Signing & Capabilities** tab.
3. Tick **Automatically manage signing** and choose your **Team**.
4. Change **Bundle Identifier** to something of your own, for example `com.yourname.ARound`. It must be unique to you.

Leave the target and scheme named `CameraAccess`. The app still shows as ARound on your phone.

## 5. iPhone Developer Mode

1. Connect the iPhone to the Mac with a cable, unlock it, and tap **Trust** if asked.
2. On the iPhone, open **Settings > Privacy & Security > Developer Mode** and turn it on. The phone restarts.
3. After the restart, confirm when the phone asks whether to turn on Developer Mode.

The Developer Mode switch only appears after the phone has been connected to Xcode once.

## 6. Meta glasses Developer Mode

This lets apps you build yourself use the glasses.

1. Open the **Meta AI** app on the iPhone.
2. Go to **Settings** (the gear icon).
3. Tap **App Info**.
4. Tap the **App version** number five times.
5. Go back to Settings and turn on the new **Developer Mode** switch.

Make sure the glasses are paired, charged and on the software version Meta requires.

### If you are not using Developer Mode

To run without Developer Mode, register an app in Meta's [Wearables Developer Center](https://wearables.developer.meta.com/) and set its ID and client token as the `META_APP_ID` and `CLIENT_TOKEN` build settings on the CameraAccess target. They feed the `MWDAT` section of `Info.plist`. In Developer Mode you can leave them empty.

## 7. Build and install

1. In the bar at the top of Xcode, choose your iPhone next to the `CameraAccess` scheme.
2. Press **Cmd+R**.
3. The first run on a phone can spend 5 to 15 minutes on a "Copying…" step shown in the Xcode status bar. Keep the phone connected and unlocked.
4. If the phone says the developer is not trusted, open **Settings > General > VPN & Device Management**, tap your Apple ID, and choose **Trust**. Then press Cmd+R again.

## 8. First run

1. Open ARound and tap **Connect my Glasses**. The Meta AI app opens; approve the connection. You return to ARound.
2. Allow the permissions as they are requested:

   | Permission | Why |
   |---|---|
   | Bluetooth | Talking to the glasses |
   | Microphone | Hearing your questions |
   | Location (While Using) | Telling the guide where you are and finding nearby places |
   | Speech Recognition | Hearing the wake phrase on the phone while the guide is asleep |
   | Glasses camera (in the Meta AI app) | Letting the guide see what you see |

3. Tap **Let's explore**. Wait for the green **Gemini** and **GPS** pills at the top.
4. Ask "Where am I?" and then "What am I looking at?"

Set **Camera detail** to Med or High on the home screen if the guide struggles to read signs.

## Troubleshooting

| Problem | What to do |
|---|---|
| Build fails with "Cannot find 'Secrets' in scope" or a missing `Secrets.swift` | Do step 3: copy `Secrets.swift.example` to `Secrets.swift` |
| "Failed to register bundle identifier" | Choose a different bundle identifier in step 4 |
| Build succeeded but the app is not on the phone | You pressed Cmd+B or a simulator is selected. Select your iPhone and press Cmd+R |
| Stuck on a "Copying…" step in the status bar | Normal on first run. Wait for it to finish |
| The app will not open after a week | Free Apple IDs sign apps for 7 days. Press Cmd+R again |
| After approving in Meta AI you land in a different app | Another app built from Meta's sample is installed and uses the same return link. ARound uses `around://`; delete or rebuild the other app |
| "Gemini is not configured" | Add your key in Settings > AI Provider, or in `Secrets.swift` and rebuild |
| The guide connects but you hear nothing | Check the glasses are the audio output, or turn on Settings > Play through phone speaker |
| The GPS pill stays yellow | Step outside or near a window. Check Settings > Privacy > Location Services allows ARound |
| "Hey ARound" does nothing | Allow Speech Recognition for ARound in iOS Settings. Tap the mic button to wake the guide in the meantime |
| Settings shows 0 packs installed | Rebuild so the built-in pack is bundled, or import the pack file from `packs/` |

## Keeping your details out of git

- Never commit `Secrets.swift`. It is already in `.gitignore`.
- Xcode writes your team ID into `project.pbxproj` when you choose a team. If you publish a fork, clear `DEVELOPMENT_TEAM` and use a neutral bundle identifier before you push.

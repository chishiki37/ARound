# Using ARound

## Starting the guide

1. Put your glasses on and open ARound.
2. Tap **Let's explore**. The glasses camera starts and the guide connects.
3. Three pills at the top tell you the state:

   | Pill | Meaning |
   |---|---|
   | **Gemini** (or **OpenAI**) | Green when the guide is connected |
   | **GPS ±8 m** | Green when the phone has a recent, precise position |
   | **Listening / Asleep / Paused** | Whether the guide can hear you |

Tap **Stop** to end the session.

## Asking questions

Speak normally. The guide answers through the glasses speakers in two or three sentences.

| Try saying | What happens |
|---|---|
| "What am I looking at?" | Names what is in front of you and tells you something about it |
| "Tell me more" | Gives the longer version |
| "Where am I?" | Describes your location in words |
| "What's around me?" | Lists the places it knows nearby |
| "What does that sign say?" | Reads visible text, if the camera can make it out |

Start talking at any time to interrupt it.

## Listening, sleeping and pausing

| State | How you get there | What is heard | How you leave |
|---|---|---|---|
| **Listening** | Start the guide, or wake it | The guide hears and sees | |
| **Asleep** | 30 seconds of quiet, the mic button, or "mute my mic", "go to sleep", "stop listening" | Only your phone, listening for the wake phrase. Nothing is sent to the AI | Say "Hey ARound", "unmute" or "wake up", or tap the mic button |
| **Paused** | Tap the side of your glasses | Nothing at all | Tap the glasses again |

A short high tone means the guide woke up. A low tone means it went to sleep.

You can ask in one breath: "Hey ARound, what am I looking at?" The phone keeps the last few seconds so the question is not cut off.

Change the wake phrase or turn off auto-sleep under **Settings > Listening**.

## How it works out what you are looking at

The guide combines several signals:

1. **Location.** GPS narrows the world to places within a few hundred metres.
2. **Direction.** Your walking direction favours what is ahead of you.
3. **Nearby places.** A live lookup from Apple Maps and Wikipedia gives named candidates, with a short summary where Wikipedia has one.
4. **Guide packs.** Curated places come first, each with a written description of what it looks like and a checked story.
5. **Reference photos.** If a pack place has photos, the phone compares them with the camera view and tells the guide which place it most resembles.
6. **The camera.** The guide looks at the frame and picks the candidate that fits, or says it cannot tell.

## Reference photos

Reference photos teach ARound what a place looks like from where you stand.

- **From the glasses:** on the guide screen, tap **Reference photo** when it appears (you must be near a pack place), then choose the place.
- **From your library:** open **Settings > Guide Packs > Manage packs**, choose a pack and a place, and tap **Add from photo library**.

Two or three photos per place from different angles work better than one. Photos stay on your phone.

## Settings

| Setting | What it does |
|---|---|
| AI Provider | Gemini Live or OpenAI, and the API key for each |
| Start guide automatically | Starts listening as soon as the glasses stream starts |
| Share location with guide | Turns all location features on or off |
| Let guide see camera | Turns camera frames to the AI on or off |
| Play through phone speaker | Uses the phone speaker instead of the glasses |
| Sleep after 30 seconds of quiet | Auto-sleep |
| Wake phrase | What you say to wake the guide |
| Guide Packs | View, import and remove packs |
| Guide instructions | The guide's personality and rules, editable |

## What leaves your phone

| Data | Goes to | When |
|---|---|---|
| Your voice and camera frames | The AI provider you chose | Only while the guide is Listening |
| GPS position and nearby places | The AI provider | When the guide checks your location |
| Coordinates | Apple Maps and Wikipedia | To look up nearby places, while location sharing is on |
| Audio while Asleep | Nowhere. Wake phrase detection runs on the phone | |
| Reference photos | Nowhere. Matching runs on the phone | |
| API keys | Stored on the phone and sent only to their own provider | |

## Limits to know about

- It is not a navigation or safety aid.
- GPS can be off by tens of metres between tall buildings and does not work indoors.
- The guide can misidentify things. It is told to say when it is unsure.
- Long sessions reconnect every several minutes with Gemini Live. The conversation so far is forgotten on a reconnect.
- The lookup of nearby places needs a connection. Packs do not.

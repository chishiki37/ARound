# Guide packs

A guide pack is a small file describing the places in one area: where each one is, what it looks like, and the story to tell. With a pack installed, ARound stops guessing from memory and matches what you see against places it has been told about.

Packs work without a connection, and they are used before the live lookup from Apple Maps and Wikipedia.

## Available packs

| Pack | Area | Places | Download |
|---|---|---|---|
| Singapore Civic District and River | Merlion Park to Raffles Hotel, about 2.5 km on foot | 12 | [pack-singapore-civic-district.json](../packs/pack-singapore-civic-district.json) |

The Singapore pack is also built into the app.

## Installing a pack

1. Get the pack file onto your iPhone: save it to the Files app, or AirDrop it.
2. In ARound, open **Settings > Guide Packs > Manage packs**.
3. Tap **Import from Files** and choose the file. Or tap **Download from a link** and paste an https link to the file.

Importing a pack with the same `id` as one you already have replaces it. Swipe a pack to remove it. Built-in packs are hidden, not erased, and **Restore built-in packs** brings them back.

## How a place is identified

Each place is recognised by four things together:

| Identifier | Fields | Used for |
|---|---|---|
| Where it is | `latitude`, `longitude`, `radius` | Deciding when the place is a candidate. `radius` is how far away, in metres, you could be standing while looking at it |
| What it is called | `name`, `aliases` | Naming it, and avoiding duplicates from the live lookup |
| What it looks like, in words | `visualCues` | The AI compares this description with the camera view |
| What it looks like, in pictures | Reference photos you add in the app | The phone compares these with the camera view |

## Writing your own pack

### 1. Pick an area

Choose 10 to 20 places you can walk between. Open spaces give better GPS than narrow streets. Indoor places will not work, because GPS does not.

### 2. Collect coordinates

For each place, find the latitude and longitude of the spot people look at, not the street address. On most map apps, press and hold on the place to see its coordinates. Use five decimal places.

### 3. Write the entries

Copy this template and fill it in. Save the file with a name that starts with `pack-` and ends with `.json`.

```json
{
  "id": "my-city-old-town",
  "name": "My City Old Town",
  "city": "My City",
  "version": 1,
  "attribution": "Where the facts came from, and their licence.",
  "route": ["clock-tower", "market-hall"],
  "places": [
    {
      "id": "clock-tower",
      "name": "Old Clock Tower",
      "aliases": ["The Clock Tower"],
      "latitude": 12.34567,
      "longitude": 98.76543,
      "radius": 100,
      "category": "clock tower",
      "visualCues": "A square red-brick tower about five storeys tall with a white clock face on each side and a green copper roof.",
      "story": "This is the Old Clock Tower, finished in 1890. It was paid for by the town's merchants.",
      "more": "The clock was made in Glasgow. The tower was restored in 2004.",
      "sources": ["https://en.wikipedia.org/wiki/Example"]
    }
  ]
}
```

| Field | Required | Guidance |
|---|---|---|
| `id` (pack) | Yes | Lowercase letters, digits and hyphens. Importing a pack with the same id replaces the old one |
| `name`, `city` | name: yes | Shown on the packs page |
| `route` | No | Place ids in walking order |
| `id` (place) | Yes | Unique within the pack. Reference photos are filed under it, so do not change it later |
| `latitude`, `longitude` | Yes | Decimal degrees |
| `radius` | No (120) | Metres. Small for a statue (50 to 80), large for a big building or a field (150 to 250) |
| `aliases` | No | Other names people and maps use |
| `category` | No | A few words: "Anglican cathedral", "historic hotel" |
| `visualCues` | Recommended | See the tips below |
| `story` | Recommended | Two or three sentences to be spoken aloud |
| `more` | No | Extra detail for "tell me more" |
| `sources` | Recommended | Links to where each fact came from |

### 4. Tips for good entries

- **Visual descriptions:** write what a stranger would see from where people stand. Colour, shape, size, material, and one thing that sets it apart from its neighbours. "Two matching cream buildings joined by a clock tower" works. "A beautiful historic theatre" does not.
- **Stories:** write for the ear. Short sentences, the name first, then one or two facts. Spell out anything awkward to say.
- **Facts:** include only what you have checked, and record the source. The guide is told not to add to a curated story unless it is sure.
- **Radius:** if two places are close together, keep the radii small so the nearer one wins.

### 5. Test it

1. Check the file is valid JSON (any online JSON checker will do).
2. Import it into ARound. The app rejects files that are not packs or have invalid coordinates, and tells you why.
3. Open the pack in the app and check the pins on the map are where you expect.
4. Walk the route. At each stop, ask "What am I looking at?" and add a reference photo or two.
5. Fix descriptions that did not match, raise the pack's `version`, and import it again.

### 6. Share it

Put the file anywhere that serves it over https, such as a public GitHub repository, and share the link. Other people can install it with **Download from a link**. To add it to this repository, open a pull request that adds the file to `packs/` and a row to the table above.

## Licensing your content

Say in `attribution` where your facts came from and under what licence. Text from Wikipedia is CC BY-SA 4.0 and needs attribution. Do not copy text from guidebooks or websites that do not allow reuse.

Reference photos are stored on each person's phone and are not part of the pack file.

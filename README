# Joker



Joker is a two-player card game built in Godot. It starts from the core idea of War, then adds hand management, card effects, wars, deck manipulation, and browser-based multiplayer through a companion ASP.NET backend.

This repository contains the Godot client project. In the current workspace, the web backend lives alongside it in the sibling folder `WarButBetterBackend` and serves the exported Godot web build.

[![Play](https://img.shields.io/badge/Play-joker.afkpals.net-1f6feb?style=for-the-badge)](https://joker.afkpals.net)
[![Backend](https://img.shields.io/badge/Backend-GitHub-24292f?style=for-the-badge&logo=github)](https://github.com/invalidunits/WarButBetterBackend)
[![Demo%20Video](https://img.shields.io/badge/Demo%20Video-YouTube-ff0000?style=for-the-badge&logo=youtube)](https://www.youtube.com/watch?v=BtAZwHTn7L8)

## Overview

- Genre: Multiplayer card game
- Engine: Godot 4.6
- Language: GDScript
- Web backend: ASP.NET Core on .NET 10
- Platform targets: Godot desktop run and Godot web export

Players draw from their own deck, manage a hand, and choose which card to play each turn. Higher-ranked cards normally capture lower-ranked cards, but many cards bend or override that rule with special effects.

## Gameplay Rules

- The game is designed for 2 players.
- Each player has a deck of 54 cards, split into 27 cards per side.
- Players play from a hand instead of only revealing the next deck card.
- Highest card captures by default.
- Card effects can override normal capture rules.
- If identical cards are played, a war begins.

### Losing Conditions

- You lose when you have no remaining cards.
- You lose if you cannot provide the required cards for a war.
- You lose if you only have jokers remaining.

### War Rules

- If both played cards are equal, both players place 3 additional cards and reveal a 4th.
- The higher revealed card captures every card currently on the table.
- If the revealed cards are equal again, the war repeats.
- If both players cannot continue a war, the result is a tie.
- If only one player cannot continue a war, the other player wins.

### Card Effects

- Joker: Burns any card permanently and self-destructs. In war it is placed face down and becomes effectless.
- 2: If captured, forces the other player to place first next turn.
- 3: If captured, lets you choose from the top 5 cards in your deck.
- 4: Shuffles the opponent's deck.
- 5: If captured, swaps one of your cards with one from the opponent's hand without revealing theirs.
- 6: Always captures anything in its suit.
- 7: Always captures 9.
- 8: No effect.
- 9: Can be played as a 6.
- 10: Disables any card effect.
- Jack: If played during war, it always captures.
- Queen: If captured, grabs a random King from your deck. If none exists, it has no effect.
- King: Both players play a random card next turn.
- Ace: Always captures unless facing a Joker. Card effects still apply whether it wins or loses.

## Repository Layout

- `Game/`: Core card and gameplay scripts.
- `GUI/`: User interface scenes, card display logic, and menu assets.
- `Scenes/`: Main game scenes, table scenes, and online scenes.
- `Documentation/`: Supplemental project documentation.
- `addons/`: Godot editor/runtime plugin content used by the project.
- `export_presets.cfg`: Web export configuration.
- `project.godot`: Godot project configuration.

## Requirements

- Godot 4.6 with GL Compatibility support
- .NET 10 SDK for the  backend
- A modern desktop browser for the web build

## Running The Project

There are two practical ways to run this project locally.

### Option 1: Run The Godot Project In The Editor

1. Open this repository in Godot.
2. Load the project using `project.godot`.
3. Run the main scene from the editor.

This is the fastest path for local gameplay and scene iteration.

### Option 2: Run The Browser Version Through ASP.NET

The web export preset in this repository points to the sibling backend path:

- `../WarButBetterBackend/WarButBetterBackend/wwwroot/index.html`

To run the web version:

1. Open this Godot project.
2. Export the Web preset so the build lands in the backend's `wwwroot` folder.
3. Start the backend from the sibling repository:

	`cd /home/main/Projects/WarButBetter/WarButBetterBackend`

	`dotnet run --project WarButBetterBackend/WarButBetterBackend.csproj`

4. Open the site in your browser at:

	`http://localhost:8080`

The current backend is configured to serve HTTP on port 8080 and uses WebSockets for live match connections.

## Multiplayer Flow

- Create a private match to generate a shareable match link.
- Join a match directly by pasting a match ID.
- Use queue matchmaking to be paired automatically.
- The browser page embeds the exported Godot web build and connects to the backend with WebSockets.

## Backend Notes

The backend currently provides:

- Match creation
- Match status polling
- Queue-based matchmaking
- WebSocket connection handling for active matches
- Cleanup of stale or abandoned matches

If you are working only in this repository, note that the backend code is not stored here. In the current workspace it exists in the sibling folder `WarButBetterBackend`.

## Documentation

Additional project notes are available here:

- `Documentation/GameDoc.md`
- `Charter.md`

## Team

- Noah Hewitt
- Dylan Reid
- Ngoc Kieu Minh Do

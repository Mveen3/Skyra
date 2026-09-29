You are a Principal Game Systems Architect and Lead Technical Director. 

I am providing you with my game concept and requirements document: `Skyra.md`.

Your objective is to produce a comprehensive, unambiguous, production-ready **Technical Game Architecture & Specification Document** for our game **"Skyra"** (a Mini Militia-inspired 2D/2.5D fast-paced combat arena shooter optimized for Linux/Ubuntu PC).
Note You dont have to write the code just give me the detailed comprehensive document.

---

### CRITICAL DOWNSTREAM OBJECTIVE:
This Technical Architecture Document will be handed over to an **Autonomous Agent** (AI coding agent). The development agent must be able to generate the **complete, runnable codebase** from scratch strictly following your specifications **WITHOUT needing to ask any clarifying questions**.

At the same time, adhere to the **Architectural Flexibility Principle**:
> Provide precise, opinionated default architectures, schemas, algorithms, and math models, but explicitly authorize the Agent to adapt or substitute specific implementation details, libraries, or patterns if it finds a more performant, modern, or cleaner approach during development.

---

### REQUIRED SECTIONS IN THE ARCHITECTURE DOCUMENT:

Please generate a deeply structured, markdown-formatted Technical Architecture Document covering each of the following sections in exhaustive technical detail:

#### 1. Executive Summary & Core Game Loop
- Game identity, target platform (Ubuntu Linux, 60+ FPS, keyboard & mouse controls, sub-1GB binary size).
- High-level game loop state machine (`INITIALIZE` -> `PRESET_MENU` -> `MATCH_LOADING` -> `SPAWNING` -> `MATCH_ACTIVE` [Loop: Input -> Physics -> AI -> Scoping -> Render -> HUD] -> `MATCH_ENDED` -> `SCORE_SUMMARY`).

#### 2. Tech Stack & Engine Evaluation (With Flexibility Clause)
- Recommend the optimal engine/framework for Linux desktop (e.g., Godot 4 via C#/GDScript, Raylib C/C++, Pygame-CE / Arcade, or Rust Bevy / Electron-Phaser desktop build).
- Analyze performance, lightweight distribution, Linux native packaging, and ease of automated code generation.
- **Architectural Flexibility Clause**: Provide clear instructions that the dev agent may select between the recommended stack or its preferred stack, provided it runs natively and smoothly on Linux without bloated dependencies.

#### 3. Core Mechanics & Physics Engine Specifications
- **Movement & Jetpack**: Exact formulas and acceleration curves for horizontal traversal, jumping, gravity, jetpack thrust, fuel depletion rate, fuel recharge delay, and terminal velocity.
- **Dynamic Camera & Scope System**:
  - Detailed camera viewport logic supporting dynamic zooming based on the equipped weapon (from 1x baseline for Magnum up to 5x max zoom for the M93BA Sniper).
  - Smooth camera interpolation (lerp) toward mouse aim offset and zoom factor.
- **Rocket Boost Mechanic**: Timed pickup spawn manager (randomly at predefined drop sockets, exactly 1 active at a time), buff duration, speed/thrust multiplier, and particle FX states.
- **Player Lifecycle & Invulnerability**: Respawn cooldown (2.0s), 2.0s post-spawn bot-invisibility/invincibility state machine, and visual alpha/stealth shader effect.

#### 4. Combat, Weapon Systems & Projectile Mathematics
- Complete Weapon Parameter Matrix covering all specified weapons:
  1. *Magnum* (Default spawn sidearm, 1x scope)
  2. *MP5* (Rapid fire SMG, low recoil, 1.5x scope)
  3. *AK-47* (High damage rifle, medium spread, 2x scope)
  4. *Pump Action Shotgun* (Multi-pellet spread, high close-range damage, 1x scope)
  5. *M93BA Sniper* (High velocity armor-piercing projectile, slow fire rate, 5x max scope)
  6. *Flamethrower* (Short-range continuous cone particle/trigger collider with damage-over-time)
  7. *PHASR* (Continuous or burst laser beam raycast with instant hit detection)
  8. *Rocket Launcher* (Slow heavy explosive projectile, radial splash damage and knockback)
  9. *Saw Gun* (Bouncing, high-speed rotary saw projectile with ricochet physics)
  10. *Hand Grenade* (Parabolic trajectory, bounce friction, 3-second fuse timer, radial fragmentation blast)
- **Simplified Pronounceable Naming Scheme**: Map each weapon to an intuitive, catchy name as requested in the requirements.
- **Inventory & Pickup Engine**: Strict 2-weapon inventory limit, weapon drop/swap keybindings, ground-weapon socket detection radius, and weapon drop distribution tables for **Mini Post** vs **Sniper Post**.

#### 5. AI Director & Bot Subsystem
- **Bot Identity**: Alpha, Beta, Gamma, Delta, Theta, Phi, Chi.
- **AI Behavior Tree / State Machine**: `PATROL` -> `TARGET_ACQUIRE` -> `ENGAGE` -> `SEEK_COVER` -> `RETREAT_RELOAD`.
- **Anti-Swarming / Pacing Director Algorithm**: Concrete logic to prevent all bots from overwhelming the human player at once (e.g., token-based combat slots where at most 2 bots aggressively engage the player simultaneously while others flank, hold positions, or patrol).
- **Bot Aiming & Perception**: Raycast line-of-sight checks, aim error/spread simulation, reaction latency, and honoring the player's 2-second stealth/invisibility window after respawn.

#### 6. Creative Map Design & Spatial Layout ("Outpost Skyra")
- Creative spatial design for the single signature map: multi-tier outpost with vertical shafts (tailored for jetpack mobility), underground bunkers for close-quarters shotgun/flamethrower duels, and elevated open ridges for long-range M93BA sniper duels.
- Grid/Coordinate blueprint, platform collision layers, boundary limits, and socket locations for:
  - Player/Bot spawn points (with distance-checking to avoid spawn camping).
  - Weapon drop points.
  - Rocket Boost powerup spawn points.

#### 7. Audio, Visuals & Zero-Blocker Asset Strategy
- **Autonomous Asset Pipeline**: Since an autonomous dev agent cannot browse commercial asset stores, define a concrete **zero-blocker strategy**:
  - Procedural/vector rendering fallbacks (clean geometric/sci-fi shapes with high-contrast color palettes, outlines, and smooth particle trails) so the game is immediately playable and visually appealing even before external assets are attached.
  - Guidelines for integrating open-source sprite sheets (e.g., Kenney.nl assets) or procedural SVG/canvas rendering.
- **Audio Engine & Cue Architecture**:
  - Sound bus breakdown (Master, SFX, Ambient, UI).
  - Specific audio events: weapon fire, reload, grenade bounce/explosion, jetpack hiss, rocket boost hum, human-kills-bot sound vs bot-kills-human sound.
  - Programmatic/synthesized audio fallback generation (e.g., retro WebAudio/WAV synthesis or lightweight PCM generation) if sound files are not provided.

#### 8. UI/UX, Controls & Profile Persistence
- **Frictionless Pre-Game Menu**:
  - 1-Click Game Launch with default settings pre-selected (Mini Post, 5 Bots, 7 Minutes).
  - Bot count selection: `[3]` `[5]` `[7]` toggle buttons.
  - Mode selection: `[Mini Post]` `[Sniper Post]`.
  - Match Duration: Stylish spin-wheel or interactive slider (5 to 10 minutes, default 7).
- **In-Game HUD**:
  - Health bar, jetpack fuel gauge, current weapon ammo + reserve, secondary weapon icon, active scope crosshair, match countdown timer, kill feed, and mini-scoreboard.
- **Input System & Keybinding Customization**:
  - Standard PC industry defaults (WASD for movement/jetpack, Mouse for 360° aim, Left Click to fire, Right Click / G for grenade, E to swap/pickup weapon, Q to toggle weapon, Space/W for jetpack thrust, R to reload, Esc to pause).
  - Keyboard/Mouse remapping UI screen.
  - Profile persistence: JSON configuration schema saved locally (e.g., `~/.config/skyra/settings.json`) preserving custom keybindings across game sessions.

#### 9. Modular Codebase Architecture & File Tree
- Complete proposed directory and file structure (e.g., `/src/core`, `/src/entities`, `/src/weapons`, `/src/ai`, `/src/physics`, `/src/ui`, `/src/audio`, `/src/config`).
- Inter-module communication design (Event Bus / Observer pattern to decouple combat events from UI and Audio).
- Concrete data models and interfaces (TypeScript interfaces, C# structs, or Python dataclasses depending on the recommended engine).

#### 10. Autonomous Implementation Milestones (Dev Agent Instructions)
- Step-by-step phased roadmap for the Game Dev Agent:
  - Phase 1: Engine initialization, display, and map collision mesh.
  - Phase 2: Player entity, jetpack physics, and camera scoping.
  - Phase 3: Weapon state machine, projectile physics, and inventory management.
  - Phase 4: Bot spawning, state machine, and anti-swarm pacing manager.
  - Phase 5: Game modes, match timer, scoring, and UI/HUD.
  - Phase 6: Sound effects, particle polish, and settings persistence.
- Explicit definition of "Done" criteria for automated verification.

---
Produce the complete, fully written architectural specification now. Ensure every table, equation, state enum, and data structure is completely written out with zero generic placeholders.


And her are my complete game idea:
"""
see i am a person who is litterly got tired how the current game is. almoast each and every game now days is full of setting and adds. few time ago i was a huge fan of mini miltia death match game specially normal outpost and sniper version of outpost. but now a days mini militia also filled with multiple unnessary map's and setting which any way doesnt reuired. 
- so my intesntion is to make a nice mini milita inspired game Named (Skyra) but better that in all aspacts, it should have following feature's 
    - simple
    - smooth
    - should have one signle but fully creative map (with two mode describe later). map should have enough challanging that a person dont get bored
    - should have two mode
        1. a normal death match (named Mini Post) where x no of of bots play against a real human player. x should be choosen in the setting. i will later completly describe what come in the settings.
        2. A sniper death match (named Sniper Post) where x no of bots play against a real human player
        - I will later describe waht kind of gun should be provided in each mode. map will be same just guns will be restricted in sniper post
        - all the maps should be enougly large as this game will be played on a laptop screen- Linux(Ubunut OS). 


- General rule for both the games:
    - A human player and x no of bots drops at random places accross the map
    - now all the x bots target is to firght with a real human, they can't fight or kill each other. bot make sure they come infront of player in few at a time and not all at a time so that the player dont get overwhelmed. also when a bot died it also get spawn at random location in the map.
    - Kepp the bot name as Alpha, Beta, Gamma, etc and Player Name as "Skyra".
    - Limit the no of bots to 7+1 human. so ask user how many bots with he want to play in setting (by showing 3, 5, 7 bots buuton). keep default 5 
    - all the characters, items (like gun, granade, etc), should looks nice and eye catchy not boring. now thisi am leaving to you that you are going to use 2d or 3d but they when still or in action should looks exciting and eye cachy. if you find some nice resource on internet which is open source and i can use for free then you can use it other wise you can create it by yourself also whcihevre you think is best for my game do that
    - the animation when a gun fires or a granade blast should be nice
    - each gun when fires and granade when blast should have unique and nice exciting sound. (you can use some nice open source sound clips for that)
    - There should be unique sound when a user killed a bot vs when a bot kills a user.
    - there should be pause and restart button in the game and should be easily accesible to the user by some shortcuts
    - The time period for each game will be set by user from 5 to 10 minutes (keep deafult 7 minutes)
    - a player spwaen to the game and score by killing bots. until the timer ends, palyer spawen again and again in the game. 
    - when a player died it spawn after 2 seconds. and after dieing when a player spawn make sure it is invisible to bots for 2 seconds
    - the scope should be set according to the gun a player is keeping in his hand like for a sniper a user might need 5x visibilty, whereas if a magnum is present then user might need just 1x visibilyt. for more detail refer the scoping mecahinsm for each gun wrok in mini miltia. and adjust that scopeing to my scoping criteria (from 1 to 5x). note that in my game each gun will be used only in its max zoom capability while being used. the hard baseline is magnum have 1x visibilty adjust other guns visibilty accoriding to that 
    - each player can carry at most two guns at a time
    - as per the game type you have to randomly drop allowed guns at a predefined locations, which (the guns) a user can change by going to that place wiht some shortcuts
    - similar to mini miltia there will be jet pack by which one can fly acroo the map. also after a certtain interval Rocket Boost should be dropeed at one or two places randomly (but one place at a time not simpulatinously)
    - one most crtical thing is when a user is playing on a pc the game should we easily palyable using keyboard buttons and mouse combination. 

-  mini Post specific settings:
    - in this following guns and grande are allowed ( i am referening the guns from mini miltia so you have to check how they work in mini militlia and there unique characterstics):
        - Magnum (Default gun with whihc a player spawn each time)
        - MP5
        - AK-47
        - Pump action shot gun
        - M93BA (its a snipet)
        - Flamethrower (its a plame thrower)
        - PHASR (its a lasor gun)
        - Rocket Launcher
        - Shaw Gun (It is a speacial gun through rotating show. for more detail chek on inernet)
-  sniper Post specific settings:
    - in this following guns and grande are allowed ( i am referening the guns from mini miltia so you have to check how they work in mini militlia and there unique characterstics):
        - M93BA (its a snipet) 
        - Hand Grande

- Gun and granade name and apearnece
    - in general guns, granade name in the game are very like a code word so i want you to make these name very easily pronuciable without any effort and also it should more like similar name of that particular gun/granade.

- charcter makeing process
    - i want that both the bot and the player should have nuique character and visual so that they looks easy catchy and make game play more soothing, exciting and enjoyable. they have nice  animation for various there variosu jobs
    - the map should made very creatively, it should be built with most creativiety and out of the box thinking, as it could make the game best palaybale game or worst game
    - i want that that each of the gun and grande should be nice colourfull and almoast similar to how they looks in realworld (you have creative freedom to those whcih does not exsit in real world like shaw gun but still they looks nice ) so that one can eaisly identify each gun without any confusion.and each should have nice animations when they are in action the same goes with granaded
    - What is best choice for making game caharacter including mpas, bots,player, guns, grandes, etc?
        - see i dont know which one will be the best so i am keeping this for you explore all the best options available
        - though few thougth are comming in my mind like On internet there are multiple open source cahracter available we can use them directly or can modify it as per our need
        - or we can create completly new chaarcater by our own and use them
        - see exaplore all the best otptin available on insternet and choose the best because this is one of the most important part of the game as this either make our game super exiting or make it compleltely boring


- Settings:
    - when a player enter to the game it is should ask for some setting before play. but these question should be asked in a very easy to answer way, so as to reduce the effort of user while answering. for now ask these question in one go in with some nice button and dont ask user to eneter some no (give button instead- again to reduce the effort)
    - NO of bots (3/5/7)
    - Type of game:
        - Mini Post:
        - Sniper Post:
    a setting icon button which further enter a detailed setting like customixing button shortcuts
    - The time period for each game will be set by user from 5 to 10 minutes (keep deafult 7 minutes). now this need an intergere entry from user but keep default as 7- intead of taking input from keyboar give a stylish spin button whihc a use can scroll to set a timer (5 to 10 minutes)
    - now once a user set all these seting few setting need to saved as user profile, so for now i want you to save those saveable setting (for now it is just one thing- button customixationa ) into some location of users pc
    - the game should have a default industry standard shortcut for keybord which offcoarse a user can chaneg
    - also try to keep every setting a deafult selection so that a user can easily enter the game without even selcecting any option just by pressing the ente game or similar button
- Practically there is no limit on size of game but try to keep its size below 1GB

"""
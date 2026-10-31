WORM RIDER  -  tame and ride Shai-Hulud in Dune: Awakening (Solo)
Version 0.1.0

Taming works like ARK's Concavenator: lure a worm, leap on, then survive the
wild ride by matching arrow prompts until the bond bar fills. Stall and it
throws you off.

REQUIREMENTS
  - Dune: Awakening on Steam (PC), update 1.5 or later, played in SOLO.
  - Nothing else. The UE4SS mod loader is included.

INSTALL
  1. Put this WormRider folder inside your game folder, usually
     C:\Program Files (x86)\Steam\steamapps\common\DuneAwakening\WormRider
  2. Double-click "Play Worm Rider.bat". Pick SOLO on the main menu.

  The launcher adds the loader only while you play and removes it when the
  game closes, so normal Steam launches (online, with BattlEye) stay stock.
  If the game ever crashes and you want to be sure, run "Remove Loader.bat".
  Mods never run on official or private servers.

HOW TO PLAY
  Lure      Plant a thumper (or just walk on open sand) and let a worm come.
  Leap on   When "SHAI-HULUD  xx m" appears, press G (or press G early to
            ready your hook). Your Shigawire Claw wires you onto its back,
            and a copy of the worm's body appears at sand height to ride on.
  Tame      Press the keys shown, in order (arrow keys or W/A/S/D).
            Each finished sequence fills the bond bar. A wrong key restarts that sequence; running
            out of time throws you off. Fill the bar 8 times to tame it.
  Ride      W surge, S slow, A/D steer, Space breach leap,
            hold Shift to drop low and sand-surf; arrow tricks while diving
            charge a speed boost.
  Dismount  G. Your worm waits. H calls it to you; G remounts when close.
  Pose      You ride sitting cross-legged on its neck. Home/End sit you
            higher or lower on the worm. F6 shows/hides the control list.
            F7 cycles other riding poses your game has loaded.
  Worm body F8 hides/shows the copy of the worm's body (made from the worm
            model in your own game). You sit on its neck behind the head and
            follow its body. PgUp/PgDn raise or lower it.

KNOWN LIMITS (v0.1)
  - Your tamed worm lasts for the play session; it is not saved.
  - The real worm stays deep under the sand; what you see and ride is the
    copy of its body. Its depth below the sand is set in sheets/config.json
    (double_sand_offset).
  - Sandstorms still hurt you while riding.
  - The game may despawn a worm at any time; the mod then drops you safely.

LOGS
  last-run.log in this folder holds the loader log from your last session.

License: MIT (see LICENSE.txt). Credits: see CREDITS.txt.
Not affiliated with or endorsed by Funcom. Dune: Awakening content stays in
your own game install; nothing from the game is included here.

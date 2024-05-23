![Brainstorm Logo](BrainstormLogo.jpg)


Note: Brainstorm requires [lovely](https://github.com/ethangreen-dev/lovely-injector) to be installed

# How to install: 
1. Install [lovely](https://github.com/ethangreen-dev/lovely-injector) and follow the installation instructions.
2. Download this repo as a ZIP, and extract it.
3. Create a directory in `%AppData%/Balatro/` and call it "Mods"
4. Place the newly extracted folder into `%AppData%/Balatro/Mods`
5. Done! You can now reload balatro and use this tool.

# Use:
- Hold `z` + 0-6 to save a state to slot
- Hold `x`+ 0-6 to load a state from slot
- Press `ctrl` + `t` to reroll the seed
- Press `ctrl` + `a` to auto-reroll for a certain tag (Default: charm tag)

# How to adjust keybinds:
1. Open up `main.lua`
2. Locate the line `-- KEYBINDS --`
3. Adjust the keybind variables to change to your desired keybinds -- Make sure to leave in the quotation marks
4. Save and exit the file, your keybinds will now be aplied when you next reload the mod! 

# How to change tag to autoreroll for:
1. Open up `main.lua`
2. Locate the line `-- AUTOREROLL CONFIG --`
3. Change the `searchTag` var to your chosen tag, using the correct name as specified in the key below.
4. Save and exit the file, and reload the game.

Example:
`searchTag = "tag_charm"` -> `searchTag = "tag_rare"`

Variable Name   | Ingame Name
-------------------------------
tag_uncommon    | Uncommon Tag
tag_rare        | Rare Tag
tag_negative    | Negative Tag
tag_holo        | Holographic Tag
tag_polychrome  | Polychrome Tag
tag_investment  | Investment Tag
tag_voucher     | Voucher Tag
tag_boss        | Boss Tag
tag_standard    | Standard Tag
tag_charm       | Charm Tag
tag_meteor      | Meteor Tag
tag_buffoon     | Buffoon Tag
tag_handy       | Handy Tag
tag_garbage     | Garbage Tag
tag_ethereal    | Ethereal Tag
tag_coupon      | Coupon Tag
tag_double      | Double Tag
tag_juggle      | Juggle Tag
tag_d_six       | D6 Tag
tag_top_up      | Top-up Tag
tag_skip        | Skip Tag
tag_orbital     | Orbital Tag
tag_economy     | Economy Tag
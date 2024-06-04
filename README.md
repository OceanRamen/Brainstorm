![Brainstorm-mod logo](BrainstormLogo.jpg)
--
## Requirements
- [Lovely](https://github.com/ethangreen-dev/lovely-injector) injector -- Get it here: https://github.com/ethangreen-dev/lovely-injector/releases

## Installation
1. Install [Lovely](https://github.com/ethangreen-dev/lovely-injector) and follow the manual installation instructions.
2. Download the [latest release](https://github.com/OceanRamen/Brainstorm/releases/) of Brainstorm.
3. Unzip the file, and place it in `.../%appdata%/balatro/mods` -- Make sure the Mod's directory name is 'Brainstorm' [^1]
4. Reload the game to activate the mod.

## Features
### Save-States
Brainstorm has the capability to save up to 10 save-states through the use of in-game key binds. 
> To create a save-state: Hold `z + 0-9`
> To load a save-state:	Hold `x + 0-9`

Each number from 0 - 9 corresponds to a save slot. To overwrite an old save, simply create a new save-state in it's slot. 

### Fast Rerolling
Brainstorm allows for super-fast rerolling through the use of an in-game key bind. 
> To fast-roll:	Press `Ctrl + t`

### Auto-Rerolling
Brainstorm can automatically reroll for parameters as specified by the user.  
By default, Auto-Reroll is configured to look for a Round 1 Charm Tag with a Soul inside. 
> To Auto-Reroll:	Press `Ctrl + a`
## Configuration
### Keybinds
To adjust key binds, 
1. Head to `.../%appdata%/balatro/mods` and locate Brainstorm
2. Open up `config.json`
3. Adjust the key bind variables below to change to your desired configuration. 
4. Save and exit the file, your new key binds will be applied when you next reload the game.
### Auto-Reroll
To change the auto-reroll config, 
1. Head to `.../%appdata%/balatro/mods` and locate Brainstorm
2. Open up `main.lua` and locate the section titled ` -- auto-reroll search config`
3. To change the Search Tag that Brainstorm looks for, edit the `searchTag` variable to your chosen tag using the correct variable name as specified in the table below. 
4. To toggle whether Brainstorm searches for a Soul in the seed's first Tarot pack, change the `searchForSoul` variable to either `true` or `false`.
5. Save and exit the file, your new key binds will be applied when you next reload the game.

Search-Tag table
In-game Name |Variable Name |
----------------|----------------|
Uncommon Tag |`tag_uncommon` |
Rare Tag |`tag_rare` |
Negative Tag |`tag_negative` |
Holographic Tag|`tag_holo` |
Polychrome Tag |`tag_polychrome` |
Investment Tag |`tag_investment` |
Voucher Tag |`tag_voucher` |
Boss Tag |`tag_boss` |
Standard Tag |`tag_standard` |
Charm Tag |`tag_charm` |
Meteor Tag |`tag_meteor` |
Buffoon Tag |`tag_buffoon` |
Handy Tag |`tag_handy` |
Garbage Tag |`tag_garbage` |
Ethereal Tag |`tag_ethereal` |
Coupon Tag |`tag_coupon` |
Double Tag |`tag_double` |
Juggle Tag |`tag_juggle` |
D6 Tag |`tag_d_six` |
Top-up Tag |`tag_top_up` |
Skip Tag |`tag_skip` |
Orbital Tag |`tag_orbital` |
Economy Tag |`tag_economy` |

[^1]: Due to current Lovely limitations, file-handling is quite a nuisance.

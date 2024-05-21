local global = {}

-- AUTOREROLL CONFIG --
searchTag = "tag_charm"

-- tag_uncommon     =     'Uncommon Tag'
-- tag_rare         =     'Rare Tag'
-- tag_negative     =     'Negative Tag'
-- tag_holo         =     'Holographic Tag'
-- tag_polychrome   =     'Polychrome Tag'
-- tag_investment   =     'Investment Tag'
-- tag_voucher      =     'Voucher Tag'
-- tag_boss         =     'Boss Tag'
-- tag_standard     =     'Standard Tag'
-- tag_charm        =     'Charm Tag'
-- tag_meteor       =     'Meteor Tag'
-- tag_buffoon      =     'Buffoon Tag'  
-- tag_handy        =     'Handy Tag'
-- tag_garbage      =     'Garbage Tag'
-- tag_ethereal     =     'Ethereal Tag'
-- tag_coupon       =     'Coupon Tag'
-- tag_double       =     'Double Tag'
-- tag_juggle       =     'Juggle Tag'
-- tag_d_six        =     'D6 Tag'    
-- tag_top_up       =     'Top-up Tag' 
-- tag_skip         =     'Skip Tag'
-- tag_orbital      =     'Orbital Tag'
-- tag_economy      =     'Economy Tag'

-- KEYBINDS --
keybinds = {    
    saveState="z",
    loadState="x",
    rerollSeed="t",
    autoreroll="a",
}

function _reroll()
    _stake = G.GAME.stake
    G:delete_run()
    G:start_run({stake = _stake})
end

function searchParametersMet()
    if not G or not G.GAME or not G.GAME.round_resets or not G.GAME.round_resets.blind_tags then
        print("One or more variables are nil or undefined")
        return false
    end

    local _tag = G.GAME.round_resets.blind_tags.Small
    if not _tag then
        print("Value of _tag is nil or undefined")
        return false
    end

    if _tag == searchTag then
        -- Check if arcana pack from skip has soul in
        return true
    else
        return false
    end
end


local sKeys = {"1", "2", "3", "4", "5", "6"}  

-- Add a flag to track if auto reroll is active
local autoRerollActive = false
local rerollInterval = 0.01  -- Time interval between rerolls (in seconds)
local rerollTimer = 0


function global.keyHandler(controller, key, dt)
    for i, k in ipairs(sKeys) do
        if key == k and love.keyboard.isDown(keybinds.saveState) then
            if G.STAGE == G.STAGES.RUN then compress_and_save(G.SETTINGS.profile .. '/' .. 'saveState' .. k .. '.jkr', G.ARGS.save_run) end
        end
        if key == k and love.keyboard.isDown(keybinds.loadState) then
            G:delete_run()
            G.SAVED_GAME = get_compressed(G.SETTINGS.profile .. '/' .. 'saveState' .. k .. '.jkr')
            if G.SAVED_GAME ~= nil then
                G.SAVED_GAME = STR_UNPACK(G.SAVED_GAME)
            end
            G:start_run({savetext = G.SAVED_GAME})
        end
    end
    if key == keybinds.rerollSeed and love.keyboard.isDown('lctrl') then
        _reroll()
    end
    if key == keybinds.autoreroll and love.keyboard.isDown('lctrl') then
        autoRerollActive = not autoRerollActive
    end
end

function global.update(dt)
    if autoRerollActive then
        rerollTimer = rerollTimer + dt
        if rerollTimer >= rerollInterval then
            rerollTimer = rerollTimer - rerollInterval
            _reroll()
            if searchParametersMet() then
                autoRerollActive = false
            end
        end
    end
end

function global.getTarot(cards)
end

return global
local global = {}

-- AUTOREROLL CONFIG --
searchTag = "tag_charm"
searchForSoul = true

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

function _auto_reroll()
    _stake = G.GAME.stake
    G:delete_run()
    --This part is meant to mimic how Balatro rerolls for Gold Stake
    local extra_num = -0.561892350821
    seed_found = nil
    while not seed_found do
        extra_num = extra_num + 0.561892350821
        seed_found = random_string(8, extra_num + extra_num + G.CONTROLLER.cursor_hover.T.x*0.33411983 + G.CONTROLLER.cursor_hover.T.y*0.874146 + 0.412311010*G.CONTROLLER.cursor_hover.time)
        global.random_state = {hashed_seed=pseudohash(seed_found)}
        _tag = pseudorandom_element(G.P_CENTER_POOLS['Tag'], global.pseudoseed('Tag1'..seed_found)).key
        if _tag == searchTag then
            if searchForSoul then
            -- Check if arcana pack from skip has The Soul
                soul_found = false
                for i = 1, 5 do
                    if pseudorandom(global.pseudoseed("soul_Tarot1"..seed_found)) > 0.997 then 
                        soul_found = true
                    end
                end
                if not soul_found then seed_found = nil end
            end
        else
            seed_found = nil
        end
    end
    G:start_run({stake = _stake, seed = seed_found})
    G.GAME.seeded = false
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
        if not searchForSoul then return true end
        -- Check if arcana pack from skip has The Soul
        global.random_state = copy_table(G.GAME.pseudorandom)
        for i = 1, 5 do
            if global.pseudorandom(global.pseudoseed("soul_Tarot1")) > 0.997 then 
                return true
            end
        end
        return false
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
            _auto_reroll()
            autoRerollActive = false
        end
    end
end

function global.getTarot(cards)
end

-- Balatro's pseudorandom functions, but referring to our copy of the RNG state instead
function global.pseudoseed(key, predict_seed)
    if key == 'seed' then return math.random() end

    if predict_seed then 
        local _pseed = pseudohash(key..(predict_seed or ''))
        _pseed = math.abs(tonumber(string.format("%.13f", (2.134453429141+_pseed*1.72431234)%1)))
        return (_pseed + (pseudohash(predict_seed) or 0))/2
    end

    if not global.random_state[key] then 
        global.random_state[key] = pseudohash(key..(global.random_state.seed or ''))
    end

    global.random_state[key] = math.abs(tonumber(string.format("%.13f", (2.134453429141+global.random_state[key]*1.72431234)%1)))
    return (global.random_state[key] + (global.random_state.hashed_seed or 0))/2
end

return global
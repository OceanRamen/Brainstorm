local global = {}

-- SETTINGS -- 
preferences = {
    printSeed=true,
}

-- KEYBINDS --
keybinds = {    
    saveState="z",
    loadState="x",
    rerollSeed="t",
}

local sKeys = {"1", "2", "3", "4", "5", "6"}   
function global.keyHandler(controller, key)
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
    if key == keybinds.rerollSeed then
        _stake = G.GAME.stake
        G:delete_run()
        G:start_run({stake = _stake})
        if printSeed == true then
            print(tostring(G.GAME.pseudorandom.seed))
        end
    end
end
return global
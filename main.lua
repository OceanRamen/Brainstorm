local global = {}
local sKeys = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0"}   
function global.keyHandler(controller, key) --  Function we patched into engine/controller.lua
    for i, k in ipairs(sKeys) do
        --  Save
        if key == k and love.keyboard.isDown("z") then
            if G.STAGE == G.STAGES.RUN then compress_and_save(G.SETTINGS.profile .. '/' .. 'saveState' .. k .. '.jkr', G.ARGS.save_run) end
        end
        --  Load
        if key == k and love.keyboard.isDown("x") then
            G:delete_run()  --  Can double as a faster reset key if slot is empty due to avoiding loading anims
            G.SAVED_GAME = get_compressed(G.SETTINGS.profile .. '/' .. 'saveState' .. k .. '.jkr')
            if G.SAVED_GAME ~= nil then
                G.SAVED_GAME = STR_UNPACK(G.SAVED_GAME)
            end
            G:start_run({savetext = G.SAVED_GAME})
        end
    end
end
return global
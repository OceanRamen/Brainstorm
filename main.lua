local global = {}

-- AUTOREROLL CONFIG --
searchTag = "tag_charm"
searchForSoul = true

rerollsPerFrame = 1000

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
    local rerollsThisFrame = 0
    --This part is meant to mimic how Balatro rerolls for Gold Stake
    local extra_num = -0.561892350821
    local seed_found = nil
    while not seed_found and rerollsThisFrame < rerollsPerFrame do
        rerollsThisFrame = rerollsThisFrame + 1
        extra_num = extra_num + 0.561892350821
        seed_found = random_string(8, extra_num + G.CONTROLLER.cursor_hover.T.x*0.33411983 + G.CONTROLLER.cursor_hover.T.y*0.874146 + 0.412311010*G.CONTROLLER.cursor_hover.time)
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
    if seed_found then
        _stake = G.GAME.stake
        G:delete_run()
        G:start_run({stake = _stake, seed = seed_found})
        G.GAME.seeded = false
    end
    return seed_found
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
            seed_found = _auto_reroll()
            if seed_found then
                autoRerollActive = false
            end
        end
    end
    if not global.reroll_text and autoRerollActive then
        global.reroll_text = global.attention_text({
            scale = 1.4, text = "Rerolling...", align = 'cm', offset = {x = 0,y = -3.5},major = G.STAGE == G.STAGES.RUN and G.play or G.title_top
        })
    end
    if global.reroll_text and not autoRerollActive then
        global.remove_attention_text(global.reroll_text)
        global.reroll_text = nil
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

--Based on Balatro's attention_text
function global.attention_text(args)
    args = args or {}
    args.text = args.text or 'test'
    args.scale = args.scale or 1
    args.colour = copy_table(args.colour or G.C.WHITE)
    args.hold = (args.hold or 0) + 0.1*(G.SPEEDFACTOR)
    args.pos = args.pos or {x = 0, y = 0}
    args.align = args.align or 'cm'
    args.emboss = args.emboss or nil

    args.fade = 1

    if args.cover then
      args.cover_colour = copy_table(args.cover_colour or G.C.RED)
      args.cover_colour_l = copy_table(lighten(args.cover_colour, 0.2))
      args.cover_colour_d = copy_table(darken(args.cover_colour, 0.2))
    else
      args.cover_colour = copy_table(G.C.CLEAR)
    end

    args.uibox_config = {
      align = args.align or 'cm',
      offset = args.offset or {x=0,y=0}, 
      major = args.cover or args.major or nil,
    }

    G.E_MANAGER:add_event(Event({
      trigger = 'after',
      delay = 0,
      blockable = false,
      blocking = false,
      func = function()
          args.AT = UIBox{
            T = {args.pos.x,args.pos.y,0,0},
            definition = 
              {n=G.UIT.ROOT, config = {align = args.cover_align or 'cm', minw = (args.cover and args.cover.T.w or 0.001) + (args.cover_padding or 0), minh = (args.cover and args.cover.T.h or 0.001) + (args.cover_padding or 0), padding = 0.03, r = 0.1, emboss = args.emboss, colour = args.cover_colour}, nodes={
                {n=G.UIT.O, config={draw_layer = 1, object = DynaText({scale = args.scale, string = args.text, maxw = args.maxw, colours = {args.colour},float = true, shadow = true, silent = not args.noisy, args.scale, pop_in = 0, pop_in_rate = 6, rotate = args.rotate or nil})}},
              }}, 
            config = args.uibox_config
          }
          args.AT.attention_text = true

          args.text = args.AT.UIRoot.children[1].config.object
          args.text:pulse(0.5)
          
          if args.cover then
            Particles(args.pos.x,args.pos.y, 0,0, {
              timer_type = 'TOTAL',
              timer = 0.01,
              pulse_max = 15,
              max = 0,
              scale = 0.3,
              vel_variation = 0.2,
              padding = 0.1,
              fill=true,
              lifespan = 0.5,
              speed = 2.5,
              attach = args.AT.UIRoot,
              colours = {args.cover_colour, args.cover_colour_l, args.cover_colour_d},
          })
          end
          if args.backdrop_colour then
            args.backdrop_colour = copy_table(args.backdrop_colour)
            Particles(args.pos.x,args.pos.y,0,0,{
              timer_type = 'TOTAL',
              timer = 5,
              scale = 2.4*(args.backdrop_scale or 1), 
              lifespan = 5,
              speed = 0,
              attach = args.AT,
              colours = {args.backdrop_colour}
            })
          end
          return true
      end
      }))
      return args
end

function global.remove_attention_text(args)
    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        delay = 0,
        blockable = false,
        blocking = false,
        func = function()
          if not args.start_time then
            args.start_time = G.TIMERS.TOTAL
            if args and args.text and args.text.pop_out then args.text:pop_out(3) end
          else
            --args.AT:align_to_attach()
            args.fade = math.max(0, 1 - 3*(G.TIMERS.TOTAL - args.start_time))
            if args.cover_colour then args.cover_colour[4] = math.min(args.cover_colour[4], 2*args.fade) end
            if args.cover_colour_l then args.cover_colour_l[4] = math.min(args.cover_colour_l[4], args.fade) end
            if args.cover_colour_d then args.cover_colour_d[4] = math.min(args.cover_colour_d[4], args.fade) end
            if args.backdrop_colour then args.backdrop_colour[4] = math.min(args.backdrop_colour[4], args.fade) end
            args.colour[4] = math.min(args.colour[4], args.fade)
            if args.fade <= 0 then
              args.AT:remove()
              return true
            end
          end
        end
      }))
end

return global
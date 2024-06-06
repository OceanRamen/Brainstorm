local lovely = require("lovely")
local nativefs = require("nativefs")

Brainstorm.SearchTagList = {"tag_uncommon", "tag_rare", "tag_holo", "tag_polychrome", "tag_investment", "tag_voucher",
                            "tag_boss", "tag_charm", "tag_juggle", "tag_double", "tag_coupon", "tag_economy",
                            "tag_skip", "tag_d_six"}

Brainstorm.G_FUNCS_options_ref = G.FUNCS.options
G.FUNCS.options = function(e)
    Brainstorm.G_FUNCS_options_ref(e)
    nativefs.write(lovely.mod_dir .. "/Brainstorm/settings.lua", STR_PACK(Brainstorm.SETTINGS))
end

function create_UIBox_settings()
    local tabs = {}
    tabs[#tabs + 1] = {
        label = localize('b_set_game'),
        chosen = true,
        tab_definition_function = G.UIDEF.settings_tab,
        tab_definition_function_args = 'Game'
    }
    if G.F_VIDEO_SETTINGS then
        tabs[#tabs + 1] = {
            label = localize('b_set_video'),
            tab_definition_function = G.UIDEF.settings_tab,
            tab_definition_function_args = 'Video'
        }
    end
    tabs[#tabs + 1] = {
        label = localize('b_set_graphics'),
        tab_definition_function = G.UIDEF.settings_tab,
        tab_definition_function_args = 'Graphics'
    }
    tabs[#tabs + 1] = {
        label = localize('b_set_audio'),
        tab_definition_function = G.UIDEF.settings_tab,
        tab_definition_function_args = 'Audio'
    }
    tabs[#tabs + 1] = {
        label = 'Brainstorm',
        tab_definition_function = (function()
            return {
                n = G.UIT.ROOT,
                config = {
                    align = "cm",
                    padding = 0.05,
                    colour = G.C.CLEAR
                },
                nodes = {
                    create_toggle({
                        label = 'Debug Mode',
                        ref_table = Brainstorm.SETTINGS,
                        ref_value = 'debug_mode',
                        callback = (function(_set_toggle)
                            _RELEASE_MODE = not Brainstorm.SETTINGS.debug_mode
                            G.F_NO_ACHIEVEMENTS = not Brainstorm.SETTINGS.debug_mode
                        end)
                    }), 
                    create_option_cycle({
                        label = "AutoReroll Search Tag",
                        scale = 0.8,
                        w = 4,
                        options = Brainstorm.SearchTagList,
                        opt_callback = 'change_search_tag',
                        current_option = Brainstorm.SETTINGS.autoreroll.searchTagID
                    }),
                    create_toggle({
                        label = 'Search For Soul',
                        ref_table = Brainstorm.SETTINGS.autoreroll,
                        ref_value = 'searchForSoul'
                    }),
                },
            }
        end),
        tab_definition_function_args = 'Brainstorm'
    }

    local t = create_UIBox_generic_options({
        back_func = 'options',
        contents = {create_tabs({
            tabs = tabs,
            tab_h = 7.05,
            tab_alignment = 'tm',
            snap_to_nav = true
        })}
    })
    return t
end

function saveManagerAlert(text)
    G.E_MANAGER:add_event(Event({
        trigger = "after",
        delay = 0.4,
        func = function()
            attention_text({
                text = text,
                scale = 0.7,
                hold = 3,
                major = G.STAGE == G.STAGES.RUN and G.play or G.title_top,
                backdrop_colour = G.C.SECONDARY_SET.Tarot,
                align = "cm",
                offset = {
                    x = 0,
                    y = -3.5
                },
                silent = true
            })
            G.E_MANAGER:add_event(Event({
                trigger = "after",
                delay = 0.06 * G.SETTINGS.GAMESPEED,
                blockable = false,
                blocking = false,
                func = function()
                    play_sound("other1", 0.76, 0.4)
                    return true
                end
            }))
            return true
        end
    }))
end

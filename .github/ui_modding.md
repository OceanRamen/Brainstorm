# Balatro UI Modding Guide

This document explains how to build custom UI using Balatro’s built-in UI engine, with a focus on creating custom settings tabs and reusable controls.

## Mental model

- The UI is a tree of nodes built from plain Lua tables. You pass that tree into `UIBox{definition=..., config=...}` to instantiate it.
- Node types are enumerated in `G.UIT` (see `globals.lua`):
  - `T` text, `B` box, `C` column, `R` row, `O` object (Sprite/DynaText/etc.), `ROOT`, `S` slider, `I` input.
- Every node table uses keys:
  - `n` (required): the node type from `G.UIT.*`.
  - `config` (optional): alignment, padding, colors, callbacks, refs, ids.
  - `nodes` (optional): array of child nodes.
- Layout is resolved by `UIElement:set_alignments` (engine/ui.lua). `config.align` letters: `c` center vertically, `m` center horizontally, `b` bottom, `r` right. Top/left are default. `padding` defaults to `G.UIT.padding`.
- `ref_table` + `ref_value` binds UI to live data; text and object refs auto-refresh when values change.
- Interactivity uses `config.button = 'name'` to invoke `G.FUNCS.name`. Helpers wire `hover`, `shadow`, etc. for you.

## Useful engine locations

- Node enums: `globals.lua` (`self.UIT = { T=1, B=2, C=3, R=4, O=5, ROOT=7, S=8, I=9 }`).
- UIBox creation, sizing, alignment: `engine/ui.lua` (class `UIBox`, `UIElement`).
- Input/callbacks for buttons, sliders, toggles, option cycles: `functions/button_callbacks.lua`.
- Prefab builders (sliders, toggles, option cycles, tabs, buttons): `functions/UI_definitions.lua` near the helper definitions.
- Settings tabs pattern: `create_UIBox_settings` and `G.UIDEF.settings_tab` in `functions/UI_definitions.lua`.

## Core building blocks (prefabs)

Use these helpers instead of raw nodes where possible:

- **Button**: `UIBox_button(args)` → clickable pill.

  - Args: `button` (G.FUNCS name), `label` array, `colour`, `minw/minh`, `choice/chosen` for toggle-style buttons, `focus_args` for controller nav.

- **Slider**: `create_slider(args)` → drag or discrete slider bound to `ref_table/ref_value`.

  - Required: `ref_table`, `ref_value`, `min`, `max` (numbers). Optional: `label`, `w/h`, `callback`, `decimal_places`, `colour`.
  - Behavior implemented by `G.FUNCS.slider` and `G.FUNCS.slider_descreet`.

- **Toggle**: `create_toggle(args)` → checkbox-style toggle bound to `ref_table/ref_value`.

  - Required: `ref_table`, `ref_value`, `label`.
  - Optional: `callback` (runs on change), `info` (array of extra text lines), `active_colour`, `inactive_colour`, `scale`.
  - Behavior: `G.FUNCS.toggle_button` and `G.FUNCS.toggle`.

- **Option Cycle**: `create_option_cycle(args)` → left/right cycle with pips.

  - Required: `options` (array), `current_option` (1-based), `opt_callback` (G.FUNCS name or nil).
  - Optional: `label`, `info`, `w/h`, `scale`, `cycle_shoulders` (adds shoulder prompts), `no_pips`.
  - Behavior: `G.FUNCS.option_cycle` updates `current_option` and `current_option_val`, fires `opt_callback`.

- **Tabs**: `create_tabs(args)` → tab strip + content area.

  - Each tab entry: `{ label=..., chosen=bool, tab_definition_function=fn, tab_definition_function_args=... }`.
  - `create_tabs` instantiates the chosen tab’s definition into `tab_contents`.
  - Useful args: `tab_h`, `tab_w`, `tab_alignment`, `snap_to_nav`, `no_shoulders`.

- **Overlay shell**: `create_UIBox_generic_options(args)` → modal frame with optional back button and infotip slot.

  - Args: `contents` (array or single node), `back_func`, `colour`, `bg_colour`, `outline_colour`, `no_back`, `snap_back`.

- **Dyn container**: `UIBox_dyn_container(inner_table, horizontal, colour_override, background_override, flipped, padding)` → framed grouping block.

- **Text input**: `create_text_input(args)` for simple keyboard input; binds to `ref_table/ref_value` with max length, prompt text.

## Making a custom settings tab (example)

Add a new tab alongside existing ones in `create_UIBox_settings` and define its builder. Example:

```lua
-- 1) Define your tab builder (anywhere after G.UIDEF exists)
function G.UIDEF.settings_tab_fancy()
  return {n=G.UIT.ROOT, config={align="cm", padding=0.05, colour=G.C.CLEAR}, nodes={
    create_toggle({label="Enable Fancy Mode", ref_table=G.SETTINGS, ref_value="fancy_mode", callback=function(val)
      G.FUNCS.apply_fancy_mode(val)
    end}),
    create_slider({label="Fancy Intensity", w=4, h=0.4, ref_table=G.SETTINGS, ref_value="fancy_intensity", min=0, max=100, callback="apply_fancy_intensity"}),
    create_option_cycle({label="Fancy Style", options={"Soft","Bold","Loud"}, current_option=1, opt_callback="set_fancy_style"})
  }}
end

-- 2) Insert the tab into the settings tabs list (in create_UIBox_settings)
tabs[#tabs+1] = {
  label = "Fancy",
  tab_definition_function = G.UIDEF.settings_tab_fancy,
  tab_definition_function_args = nil
}
```

Then implement the callbacks you referenced (e.g., `G.FUNCS.apply_fancy_mode`, `G.FUNCS.apply_fancy_intensity`, `G.FUNCS.set_fancy_style`). They’ll receive the cycle/slider/toggle configs or values per the existing callbacks in `button_callbacks.lua`.

## Making a standalone modal/panel

1. Build your content nodes using rows/cols and prefabs:

```lua
local content = {
  UIBox_button({label={"Do Thing"}, button="my_action", minw=3}),
  create_toggle({label="Flag", ref_table=G.SETTINGS, ref_value="my_flag"}),
  create_slider({label="Value", w=4, h=0.4, ref_table=G.SETTINGS, ref_value="my_val", min=0, max=10})
}
```

1. Wrap in `create_UIBox_generic_options({contents = content, back_func = "exit_overlay_menu"})` and pass that as the `definition` to a new `UIBox` to show the overlay.

## Binding data and IDs

- Use `ref_table/ref_value` on `T` nodes to auto-update text when values change.
- Use `id` in `config` to fetch elements later with `UIBox:get_UIE_by_ID(id)`.
- Objects (`n=G.UIT.O`) can wrap `Sprite`, `DynaText`, or another `UIBox` via `config.object`.

## Controller focus

- `focus_args` on interactive nodes controls navigation; helpers set sensible defaults: sliders (`type='slider'`), cycles (`type='cycle'`), tabs (`type='tab'`), buttons (`nav='wide'`, etc.).
- `snap_to_nav=true` on `create_tabs` helps initial focus within overlays.

## Gotchas

- Buttons need `hover=true` (helpers do this) and a `button` string to trigger a callback.
- If you bind text to changing data, a length change triggers a layout recalc; avoid `no_recalc` unless you really need fixed width.
- `id` values must be unique within a UIBox tree.
- Colors are premultiplied alpha tables; `colour[4]` near zero hides the element.

## Where to look in code

- Prefab helpers: `functions/UI_definitions.lua` (slider/toggle/cycle/tabs/buttons).
- Input + callbacks: `functions/button_callbacks.lua`.
- Core UI tree + layout: `engine/ui.lua`.
- Node enums/constants: `globals.lua` (G.UIT, colors in G.C).

## Extending further

- You can nest `UIBox` instances via `n=G.UIT.O` with `config.object = UIBox{definition=...}` to embed sub-UIs.
- `UIBox_dyn_container` gives quick framed blocks for grouped options.
- Use `create_text_input` if you need player text entry (e.g., seeds, names).

Keep everything data-first: assemble tables, wire callbacks in `G.FUNCS`, and let the engine handle layout and interaction.

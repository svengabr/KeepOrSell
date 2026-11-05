-- KeepOrSell's entry under Esc > Options > AddOns: one button that opens the own options window
-- (UI/OptionsWindow.lua), so players who look there still find the options.
local addonName, ns = ...
local L = ns.L

-- Blizzard's gamepad UI (Forever's controller mode) is on
function ns.IsGamepadUI()
  return C_InputInterfaceStyle ~= nil and C_InputInterfaceStyle.GetCurrentStyle ~= nil and Enum ~= nil
    and Enum.InputDeviceInterfaceType ~= nil
    and C_InputInterfaceStyle.GetCurrentStyle() == Enum.InputDeviceInterfaceType.Gamepad
end

-- Registers the entry; the button only shows the own window (above the settings panel) and never closes
-- Blizzard's panel from addon code
function ns.RegisterOptions()
  if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnCategory) then return end
  local category, layout = Settings.RegisterVerticalLayoutCategory(addonName)
  -- No search tags (last argument false): added from addon code, the tag table is tainted, and Blizzard's
  -- options search reads it on every keystroke, so unrelated protected settings (Discord display name) got blocked
  if layout and CreateSettingsButtonInitializer then
    layout:AddInitializer(CreateSettingsButtonInitializer(L.OPT_WINDOW_OPEN, L.OPT_WINDOW_OPEN_BUTTON,
      function() ns.ShowOptionsWindow() end, L.OPT_WINDOW_OPEN_TIP, false))
  end
  Settings.RegisterAddOnCategory(category)
end

-- The help button and the hints open the options
function ns.OpenOptions()
  ns.ShowOptionsWindow()
end

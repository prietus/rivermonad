{-# LANGUAGE LambdaCase #-}
-- ~/.config/waymobar/waymobar.hs
--
-- waymobar rebuilds this file when it changes; check it with
-- `waymobar --recompile`. Reload: `pkill -x waymobar-aarch6; waymobar &`
-- Docs: https://github.com/prietus/waymobar
import Data.List (isInfixOf, stripPrefix)
import Data.Maybe (fromMaybe)

import Waymobar

-- Catppuccin Mocha (same palette as rivermonad's borders, foot, fuzzel, mako)
base, surface0, surface1, overlay0, subtext, text', mauve, blue, sky, teal,
  green, yellow, peach, red, pink :: String
base     = "#1e1e2e"; surface0 = "#313244"; surface1 = "#45475a"
overlay0 = "#6c7086"; subtext  = "#a6adc8"; text'    = "#cdd6f4"
mauve    = "#cba6f7"; blue     = "#89b4fa"; sky      = "#89dceb"
teal     = "#94e2d5"; green    = "#a6e3a1"; yellow   = "#f9e2af"
peach    = "#fab387"; red      = "#f38ba8"; pink     = "#f5c2e7"

------------------------------------------------------------------------------
-- Pill theme: a transparent bar where every widget is a rounded "island".
-- The bar is 28 px high and floats 6 px from the screen edges (the same gap
-- rivermonad leaves between windows); a pill fills the bar's height.
-- Icons are colour emoji (Noto Color Emoji, through pango's font fallback),
-- except the workspaces, CPU and memory, which use Nerd Font glyphs.

-- | The look of every pill: slightly translucent, no border.
pill :: Style
pill = noStyle
  { styleBg      = Just (base ++ "e6")
  , styleRadius  = Just 14
  , stylePadding = Just 13
  }

-- | Pills that react to the pointer (the clickable ones).
clickablePill :: Style
clickablePill = pill { styleHover = Just noStyle { styleBg = Just surface0 } }

-- | Put a widget in its own pill. 'baseStyle' keeps the widget's own colours.
inPill, inClickablePill :: Widget -> Widget
inPill = baseStyle pill
inClickablePill = baseStyle clickablePill

main :: IO ()
main = waymobar def
  { font = "Inter Medium 10"
  , barHeight = 28
  , margins = (6, 6, 0, 6)   -- floating: same 6 px as rivermonad's gapsWithEdge 6
  , bgColor = "#00000000"    -- transparent: only the pills are drawn
  , fgColor = text'
  , popoverBg = Just (base ++ "f7")   -- menus and hover panels: nearly opaque
  , popoverRadius = 14
  , menuBorder = surface1
  , menuHighlight = surface0
  , widgetSpacing = 6
  , edgePadding = 0
  , left =
      [ myWorkspaces
      , inClickablePill (layoutName layoutLabel)
      ]
  , center = [ inPill (colored subtext (windowTitle 80)) ]
  , right =
      [ inClickablePill media
      , inClickablePill myNetwork
      , inClickablePill myWeather
      , inClickablePill myVolume
      , inPill (cpu (\p -> ic peach icCpu ++ warn 80 p (num (show p ++ "%"))))
      , inPill (memory (\p -> ic yellow icMem ++ warn 85 p (num (show p ++ "%"))))
      , inPill (battery (\p st -> em (batteryIcon p st)
                                    ++ warn' (p <= 15 && st /= "Charging") (num (show p ++ "%"))))
      -- one pill around all the tray icons
      , groupStyle pill { stylePadding = Just 8 } (tray defaultTray { traySymbolicColor = text' })
      , inPill (markup clockMarkup (clock "%a %d %b|%H:%M"))
        -- log out: asks to confirm, closes every window, then back to GDM
      , inClickablePill (colored red (logoutButton "<span size='larger'>⏻</span>"))
      ]
  }

-- | An emoji (slightly larger than the text) followed by a space.
em :: String -> String
em e = "<span size='larger'>" ++ e ++ "</span>  "

-- | A coloured Nerd Font glyph followed by a space.
ic :: String -> String -> String
ic color glyph = "<span size='larger' foreground='" ++ color ++ "'>" ++ glyph ++ "</span>  "

-- Nerd Font icons (the "Symbols Nerd Font"; any glyph from
-- https://www.nerdfonts.com/cheat-sheet works).
icCpu, icMem :: String
icCpu = "\xf2db"    -- nf-fa-microchip
icMem = "\xf035b"   -- nf-md-memory

-- | Tabular figures, so the pills don't change width as the numbers do.
num :: String -> String
num s = "<span font_features='tnum'>" ++ s ++ "</span>"

-- | 'clock' escapes its text, so the icons and the bold time are added
-- afterwards: "Thu 12 Nov|20:37" is split at the bar.
clockMarkup :: String -> String
clockMarkup s = em "📅" ++ day ++ "    " ++ em "🕒" ++ num ("<b>" ++ drop 1 time ++ "</b>")
  where (day, time) = break (== '|') s

-- Battery: 🔋, 🪫 when low, with ⚡ while charging.
batteryIcon :: Int -> String -> String
batteryIcon p st = (if st == "Charging" then "⚡" else "") ++ (if p <= 15 then "🪫" else "🔋")

-- Nerd Font icons in front of the named workspaces.
wsIcon :: String -> String
wsIcon "web"  = em "\xf269"   -- nf-fa-firefox
wsIcon "code" = em "\xf121"   -- nf-fa-code
wsIcon "term" = em "\xf120"   -- nf-fa-terminal
wsIcon _      = ""

-- web/code/term always; numbered workspaces only when they have windows or
-- are on screen (a block with an empty label is not drawn).
myWorkspaces :: Widget
myWorkspaces = workspaces defaultWorkspaces
  { wsLabel = \w ->
      if wsName w `elem` ["web", "code", "term"] || wsWindows w > 0 || wsVisible w
        then wsIcon (wsName w) ++ escape (wsName w)
        else ""
  , wsPadding = 11
    -- each workspace is a small pill inside the big one
  , focusedStyle = wsPill { styleFg = Just base, styleBg = Just mauve }
  , activeStyle  = wsPill { styleBg = Just surface1 }                    -- on this monitor
  , visibleStyle = wsHover { styleFg = Just yellow }                     -- on the other monitor
  , hiddenStyle  = wsHover { styleFg = Just subtext }
  , emptyStyle   = wsHover { styleFg = Just overlay0 }
  }
  & groupStyle pill { stylePadding = Just 3 }   -- the big pill around them
  where
    wsPill = noStyle { styleRadius = Just 11, styleMargin = Just (3, 1) }
    wsHover = wsPill { styleHover = Just noStyle { styleBg = Just surface0 } }
    w & f = f w

-- The layout as an emoji plus its name ("Spacing Tall" -> "Tall").
layoutLabel :: String -> String
layoutLabel l = em glyph ++ "<span foreground='" ++ subtext ++ "'>" ++ escape name ++ "</span>"
  where
    name = fromMaybe l (stripPrefix "Spacing " l)
    glyph | "Full" `isInfixOf` name     = "🖥️"
          | "Mirror" `isInfixOf` name   = "🔃"
          | "ThreeCol" `isInfixOf` name = "🏛️"
          | otherwise                   = "🪟"

-- Volume of the default output, live through pipewire-pulse: click mutes,
-- the wheel changes it (up to 100%).
myVolume :: Widget
myVolume = volume $ \case
  Nothing -> ""
  Just v
    | volMuted v -> em "🔇" ++ "<span foreground='" ++ overlay0 ++ "'>muted</span>"
    | otherwise  -> em (if volPercent v < 50 then "🔉" else "🔊") ++ num (show (volPercent v) ++ "%")

-- The connection: the Wi-Fi network (or the wired interface). With the
-- pointer on it, a panel shows the details (band, addresses, router, link
-- speed, traffic); a click opens the Wi-Fi menu (networks in range, radio
-- on/off), like the one of macOS.
myNetwork :: Widget
myNetwork = wifiMenu $ networkHover 3 label (maybe "" networkDetails)
  where
    label Nothing = em "🚫" ++ "<span foreground='" ++ overlay0 ++ "'>offline</span>"
    label (Just n)
      | netKind n == Wifi = em "📶" ++ escape (fromMaybe "Wi-Fi" (netName n))
      | otherwise         = em "🔌" ++ escape (netInterface n)

-- The weather (Open-Meteo), located from the public IP address; pin it with
-- `weatherLocation = City "Sevilla"` or `Coords 37.38 (-5.98)`. Click
-- refreshes; with the pointer on it, a panel shows the details.
myWeather :: Widget
myWeather = weather defaultWeather { weatherHover = details } $ \case
  Nothing -> ""
  Just w -> em (weatherEmoji w) ++ num (show (weatherTemp w) ++ "°")
  where
    -- The panel: the temperature in big, the place and the sky, and a
    -- small grid with today's extremes, the humidity and the wind.
    details w = "<span line_height='1.3'>"
      ++ "<span size='220%'>" ++ weatherEmoji w ++ " <b>" ++ num (show (weatherTemp w) ++ "°") ++ "</b></span>\n"
      ++ (if null (weatherPlace w) then "" else "<b>" ++ escape (weatherPlace w) ++ "</b>\n")
      ++ dim (escape (weatherDescription w) ++ " · feels like " ++ show (weatherFeelsLike w) ++ "°") ++ "\n"
      ++ "<span size='40%'> </span>\n"
      ++ cell "⬆️" (show (weatherTempMax w) ++ "°") ++ cell "⬇️" (show (weatherTempMin w) ++ "°") ++ "\n"
      ++ cell "💧" (show (weatherHumidity w) ++ "%") ++ cell "💨" (show (weatherWind w) ++ " km/h")
      ++ "</span>"
    -- an emoji and its value; the tab lines the second column up
    cell e v = e ++ "  " ++ num v ++ "\t"
    dim s = "<span foreground='" ++ subtext ++ "'>" ++ s ++ "</span>"

-- The current media player: left click play/pause, right click next,
-- middle click previous. Hidden when nothing is playing or paused.
media :: Widget
media = mpris $ \m ->
  if mediaStatus m == Stopped then "" else
    em (if mediaStatus m == Playing then "▶️" else "⏸️")
      ++ escape (shorten 40 (if null (mediaArtist m) then mediaTitle m else mediaArtist m ++ " - " ++ mediaTitle m))

warn :: Int -> Int -> String -> String
warn limit p = warn' (p >= limit)

warn' :: Bool -> String -> String
warn' True s = "<span foreground='" ++ red ++ "'>" ++ s ++ "</span>"
warn' False s = s

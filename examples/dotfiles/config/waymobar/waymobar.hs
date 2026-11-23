{-# LANGUAGE LambdaCase #-}
-- ~/.config/waymobar/waymobar.hs
--
-- waymobar rebuilds this file when it changes; check it with
-- `waymobar --recompile`. Reload: `pkill -x waymobar-aarch6; waymobar &`
-- Docs: https://github.com/prietus/waymobar
import Data.List (isInfixOf, stripPrefix)
import Data.Maybe (fromMaybe)
import Control.Exception (SomeException, try)
import Data.IORef (newIORef, readIORef, writeIORef)
import GHC.Clock (getMonotonicTime)
import System.Environment (lookupEnv)

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
-- Icons are Material Symbols (the variable font, "Rounded" cut, filled),
-- drawn in white; see 'sym' below.

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
    -- volume, brightness and keyboard layout changes, for a moment
  , osd = Just myOsd
    -- hot corners: rest the pointer in the corner a moment
  , hotCorners =
      [ (TopLeftCorner, spawn "spacelet")      -- the overview of the workspaces
      , (BottomRightCorner, spawn "locklet")   -- lock the screen (locklet)
      ]
  , left =
      [ myWorkspaces
      , inClickablePill (layoutName layoutLabel)
      , inPill hiddenWindows
      ]
    -- the open windows of this workspace (and the minimised ones)
  , center = [ myTaskbar ]
  , right =
      [ inClickablePill media
      , inClickablePill myNetwork
      , inClickablePill myWeather
      , inClickablePill myVolume
      , inClickablePill myNotifications
      , inPill (cpu (\p -> sym "memory" ++ warn 80 p (num (show p ++ "%"))))
      , inPill (memory (\p -> sym "memory_alt" ++ warn 85 p (num (show p ++ "%"))))
      , inPill (battery (\p st -> sym (batteryIcon p st)
                                    ++ warn' (p <= 15 && st /= "Charging") (num (show p ++ "%"))))
      , inClickablePill screenshot
      -- one pill around all the tray icons
      , groupStyle pill { stylePadding = Just 8 } (tray defaultTray { traySymbolicColor = white })
        -- the date is also the calendar: the agenda opens with the pointer on it
      , inClickablePill (withCalendar myCalendar (clock "%a %d %b|%H:%M"))
        -- log out: asks to confirm, closes every window, then back to GDM
      , inClickablePill (logoutButton (sym1 "power_settings_new"))
      ]
  }

-- | The colour of the icons.
white :: String
white = "#ffffff"

-- | The icon font. Others: "Material Symbols Outlined", "Material Symbols
-- Sharp"; "@FILL=0" gives the outlined drawing, "@wght=300" thinner strokes.
iconFont, iconAxes :: String
iconFont = "Material Symbols Rounded"
iconAxes = "@FILL=1"

-- | A Material Symbols icon by its name (https://fonts.google.com/icons:
-- "wifi", "volume_up"...), in white, followed by a space.
sym :: String -> String
sym name = sym1 name ++ "  "

-- | The same without the space.
sym1 :: String -> String
sym1 = iconAt 14 white

-- | An icon at a size in points and in a colour. The icons are bigger than
-- the text, so they are lowered to stay centred on the line.
iconAt :: Int -> String -> String -> String
iconAt size color name =
  "<span font_desc='" ++ iconFont ++ " " ++ show size ++ " " ++ iconAxes
    ++ "' rise='" ++ show (negate (size * 215)) ++ "' foreground='" ++ color ++ "'>"
    ++ name ++ "</span>"

-- | An icon that takes the colour of the text around it (the workspaces,
-- whose colour depends on their state).
symPlain :: String -> String
symPlain name =
  "<span font_desc='" ++ iconFont ++ " 14 " ++ iconAxes ++ "' rise='-3010'>" ++ name ++ "</span>  "

-- | Tabular figures, so the pills don't change width as the numbers do.
num :: String -> String
num s = "<span font_features='tnum'>" ++ s ++ "</span>"

-- The calendars shown under the date. Add your accounts to the list, for
-- iCloud:
--
-- >   [ ICloud "me@icloud.com" (PasswordFile "~/.config/waymobar/icloud-password") ]
--
-- with an app-specific password (appleid.apple.com > Sign-In and Security >
-- App-Specific Passwords) as the first line of that file (chmod 600): the
-- password never goes in this file. A click on the date fetches the events
-- again.
myCalendar :: CalendarConfig
myCalendar = defaultCalendar
  { calendarAccounts = []
  , calendarMarkup = clockMarkup
  }

-- | 'clock' escapes its text, so the icons and the bold time are added
-- afterwards: "Thu 12 Nov|20:37" is split at the bar. When there are
-- events left today, the calendar icon gets a mark and the colour of the
-- next one's calendar.
clockMarkup :: Agenda -> String -> String
clockMarkup a s = dateIcon ++ "  " ++ day ++ "    " ++ sym "schedule" ++ num ("<b>" ++ drop 1 time ++ "</b>")
  where
    (day, time) = break (== '|') s
    dateIcon = case agendaToday a of
      e : _ -> iconAt 14 (fromMaybe mauve (eventColor e)) "event"
      []    -> sym1 "calendar_today"

-- Battery: the level in seven steps, a bolt while charging, an alert when low.
batteryIcon :: Int -> String -> String
batteryIcon p st
  | st == "Charging" = "battery_charging_full"
  | p <= 15          = "battery_alert"
  | p >= 95          = "battery_full"
  | otherwise        = "battery_" ++ show (min 6 (p * 7 `div` 100)) ++ "_bar"

-- Icons in front of the named workspaces (in the colour of the workspace).
wsIcon :: String -> String
wsIcon "web"  = symPlain "language"
wsIcon "code" = symPlain "code"
wsIcon "term" = symPlain "terminal"
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

-- The layout as an icon plus its name ("Spacing Tall" -> "Tall").
layoutLabel :: String -> String
layoutLabel l = sym glyph ++ "<span foreground='" ++ subtext ++ "'>" ++ escape name ++ "</span>"
  where
    name = fromMaybe l (stripPrefix "Spacing " l)
    glyph | "Full" `isInfixOf` name     = "fullscreen"
          | "Mirror" `isInfixOf` name   = "splitscreen_top"
          | "ThreeCol" `isInfixOf` name = "view_week"
          | otherwise                   = "view_sidebar"

-- Volume of the default output, live through pipewire-pulse: click mutes,
-- the wheel changes it (up to 100%).
myVolume :: Widget
myVolume = volume $ \case
  Nothing -> ""
  Just v
    | volMuted v -> sym "volume_off" ++ "<span foreground='" ++ overlay0 ++ "'>muted</span>"
    | otherwise  -> sym (if volPercent v < 50 then "volume_down" else "volume_up") ++ num (show (volPercent v) ++ "%")

-- The connection: the Wi-Fi network (or the wired interface). With the
-- pointer on it, a panel shows the details (band, addresses, router, link
-- speed, traffic); a click opens the Wi-Fi menu (networks in range, radio
-- on/off), like the one of macOS.
myNetwork :: Widget
myNetwork = wifiMenu $ networkHover 3 label (maybe "" networkDetails)
  where
    label Nothing = sym "wifi_off" ++ "<span foreground='" ++ overlay0 ++ "'>offline</span>"
    label (Just n)
      | netKind n == Wifi = sym "wifi" ++ escape (fromMaybe "Wi-Fi" (netName n))
      | otherwise         = sym "lan" ++ escape (netInterface n)

-- The weather (Open-Meteo), located from the public IP address; pin it with
-- `weatherLocation = City "Madrid"` or `Coords 40.42 (-3.70)`. Click
-- refreshes; with the pointer on it, a panel shows the details.
myWeather :: Widget
myWeather = weather defaultWeather { weatherHover = details } $ \case
  Nothing -> ""
  Just w -> sym (weatherSymbol w) ++ num (show (weatherTemp w) ++ "°")
  where
    -- The panel: the temperature in big, the place and the sky, and a
    -- small grid with today's extremes, the humidity and the wind.
    details w = "<span line_height='1.3'>"
      ++ iconAt 26 white (weatherSymbol w) ++ "<span size='220%'> <b>" ++ num (show (weatherTemp w) ++ "°") ++ "</b></span>\n"
      ++ (if null (weatherPlace w) then "" else "<b>" ++ escape (weatherPlace w) ++ "</b>\n")
      ++ dim (escape (weatherDescription w) ++ " · feels like " ++ show (weatherFeelsLike w) ++ "°") ++ "\n"
      ++ "<span size='40%'> </span>\n"
      ++ cell "arrow_upward" (show (weatherTempMax w) ++ "°") ++ cell "arrow_downward" (show (weatherTempMin w) ++ "°") ++ "\n"
      ++ cell "humidity_percentage" (show (weatherHumidity w) ++ "%") ++ cell "air" (show (weatherWind w) ++ " km/h")
      ++ "</span>"
    -- an icon and its value; the tab lines the second column up
    cell e v = sym e ++ num v ++ "\t"
    dim s = "<span foreground='" ++ subtext ++ "'>" ++ s ++ "</span>"

-- The Material Symbols icon for the weather code (WMO), day or night.
weatherSymbol :: Weather -> String
weatherSymbol w = case weatherCode w of
  0 -> dn "clear_day" "bedtime"
  1 -> dn "partly_cloudy_day" "partly_cloudy_night"
  2 -> dn "partly_cloudy_day" "partly_cloudy_night"
  3 -> "cloud"
  c | c `elem` [45, 48] -> "foggy"
    | c `elem` [56, 57, 66, 67] -> "weather_mix"            -- freezing
    | c `elem` [51, 53, 55, 61, 63, 65, 80, 81, 82] -> "rainy"
    | c `elem` [71, 73, 75, 77, 85, 86] -> "weather_snowy"
    | c `elem` [95, 96, 99] -> "thunderstorm"
    | otherwise -> "help"
  where
    dn d n = if weatherIsDay w then d else n

-- The current media player: left click play/pause, right click next,
-- middle click previous. Hidden when nothing is playing or paused.
media :: Widget
media = mpris $ \m ->
  if mediaStatus m == Stopped then "" else
    sym (if mediaStatus m == Playing then "play_arrow" else "pause")
      ++ escape (shorten 40 (if null (mediaArtist m) then mediaTitle m else mediaArtist m ++ " - " ++ mediaTitle m))

-- Screenshots and screen recordings (https://github.com/prietus/shotlet): a click opens a toolbar
-- like the one of macOS (screen, window, region, record; timer and the rest
-- under Options). While a recording runs this shows its duration in red,
-- and a click stops it.
screenshot :: Widget
screenshot = spawnOnClick "shotlet" $ periodicIO 1 $ do
  started <- newIORef Nothing              -- when this recording was first seen
  pure $ do
    dir <- fromMaybe "/tmp" <$> lookupEnv "XDG_RUNTIME_DIR"
    -- "PID\nFILE", written when a recording starts
    pid <- either (const "") (takeWhile (/= '\n')) <$> readFile' (dir ++ "/screenrec")
    alive <- if null pid then pure False else either (const False) (const True) <$> readFile' ("/proc/" ++ pid ++ "/comm")
    now <- getMonotonicTime
    if not alive then writeIORef started Nothing >> pure (sym1 "screenshot_region") else do
      t0 <- maybe (writeIORef started (Just now) >> pure now) pure =<< readIORef started
      let secs = round (now - t0) :: Int
          two n = (if n < 10 then "0" else "") ++ show n
      pure (iconAt 14 red "stop_circle" ++ "  <span foreground='" ++ red ++ "'>"
              ++ num (show (secs `div` 60) ++ ":" ++ two (secs `mod` 60)) ++ "</span>")
  where
    readFile' :: FilePath -> IO (Either SomeException String)
    readFile' p = try (readFile p >>= \c -> length c `seq` pure c)

warn :: Int -> Int -> String -> String
warn limit p = warn' (p >= limit)

warn' :: Bool -> String -> String
warn' True s = "<span foreground='" ++ red ++ "'>" ++ s ++ "</span>"
warn' False s = s

-- Windows hidden with M-S-o (rivermonad's "hidden" workspace): an eye with
-- a line through it and how many; nothing when there are none. M-o brings
-- them back, the last one first.
hiddenWindows :: Widget
hiddenWindows = Widget $ \env -> pure $ \_ -> do
  mst <- rivermonadState env
  let n = sum [ wsWindows w | Just st <- [mst], w <- rsWorkspaces st, wsName w == "hidden" ]
  pure [ block (sym "visibility_off" ++ num (show n)) | n > 0 ]

-- Notifications from mako: a bell (crossed out in "do not disturb") and how
-- many arrived since you last looked. A click lists the recent ones (and
-- "do not disturb"); the right button switches "do not disturb".
myNotifications :: Widget
myNotifications = notifications defaultNotifications
  { notifLabel = \st ->
      (if nsDnd st then sym1 "notifications_off" else sym1 "notifications")
        ++ (if nsUnseen st > 0
              then "  <span foreground='" ++ mauve ++ "'><b>" ++ num (show (nsUnseen st)) ++ "</b></span>"
              else "")
  }

-- The on-screen display, with the bar's icons and colours.
myOsd :: OsdConfig
myOsd = defaultOsd
  { osdBarColor = mauve
  , osdVolumeLabel = \muted p ->
      if muted then sym "volume_off" ++ "Muted"
      else sym (if p < 50 then "volume_down" else "volume_up") ++ "Volume  " ++ num (show p ++ "%")
  , osdBrightnessLabel = \p -> sym "brightness_6" ++ "Brightness  " ++ num (show p ++ "%")
  , osdLayoutLabel = \l -> sym "keyboard" ++ escape l
  }

-- The task bar: each window a small pill with its icon and title, the
-- focused one lit like the focused workspace, minimised ones dimmed. Click
-- focuses, middle click closes, right click: move it or close it.
myTaskbar :: Widget
myTaskbar = taskbar defaultTaskbar
  { tbLabel = \w -> "<span foreground='" ++ (if winFocused w then text' else if winHidden w then overlay0 else subtext) ++ "'>"
                    ++ escape (shorten 22 (winTitle w)) ++ "</span>"
  , tbFocusedStyle = tbPill { styleBg = Just surface1 }
  , tbNormalStyle  = tbPill { styleHover = Just noStyle { styleBg = Just surface0 } }
  , tbHiddenStyle  = tbPill { styleFg = Just overlay0, styleHover = Just noStyle { styleBg = Just surface0 } }
  , tbIconSize = 16
  , tbPadding = 10
  }
  & groupStyle pill { stylePadding = Just 3 }   -- one big pill around them
  where
    tbPill = noStyle { styleRadius = Just 11, styleMargin = Just (3, 1) }
    w & f = f w
